using System;
using System.Collections;
using System.Text;
using System.Diagnostics;
namespace Parsive;

//Holds onto info used by top-down backtracked parsers of byte arrays
public class ParserData
{
	public StringView       source;
	public int              pos;
	public List<TrackPoint> track;
	public List<Remark>     remarks;

	public ~this() {
		Debug.Assert(track.Count == 0);
		delete track;
		DeleteContainerAndItems!(remarks);
	}
	
	[Inline] public StringView RawSymbol
		=> source[track.Back.pos..<pos];

	[Inline] public int LengthLeft
		=> source.Length - pos;

	public int LengthLeftUntilTerminator(uint8 terminatorByte) {
		let length = source.Length;
		var i = pos;
		while (i < length && terminatorByte != (.)source[i])
			i++;
		return i - pos;
	}

	[AllowAppend]
	public this(StringView raw, int startPos = 0) {
		pos = startPos;
		source = raw;
		track = new .(16);
		remarks = new .(16);
	}

	public void FullReset(StringView newSource, int start = 0) {
		if (newSource != default)
			source = newSource;

		pos = start;
		track.Clear();
		ClearAndDeleteItems(remarks);
	}
	
	public void Start(StringView name = default)
		=> track.Add(.(pos, name));

	public Parsed<T> Ok<T>(T v) {
		track.PopBack();
		return .() {
			HasValue = true,
			ValueOrDefault = v
		};
	}

	public ParserErr Err() {
		pos = track.PopBack().pos;
		for (var i = remarks.Count - 1; i >= 0; i--) {
			let remark = remarks[i];
			if (remark.FinalPos < pos)
				break;

			if (remark.RemoveOnBacktrack()) {
				delete remark;
				remarks.RemoveAt(i);
			}
		}
		return default;
	}

	public struct TrackPoint: this(int pos, StringView name);

	public enum RemarkType
	{
		case Unknown;
		case Other(StringView name, bool removeOnBacktrack);
		case SymbolRange; //for syntax highlighters
		case Error;       //parsing fatally failed
		case SoftError;   //parsing partially failed
		case Warning;     //parsing didn't fail at all, even though input was wrong/deprecated
		case Suggestion;  //parsing didn't fail at all, but input could be prettier

		public override void ToString(String strBuffer) {
			switch (this) {
			case Other(let name, ?): strBuffer.Append(name);
			case SymbolRange:        strBuffer.Append(nameof(SymbolRange));
			case Error:              strBuffer.Append(nameof(Error));
			case SoftError:          strBuffer.Append(nameof(SoftError));
			case Warning:            strBuffer.Append(nameof(Warning));
			case Suggestion:         strBuffer.Append(nameof(Suggestion));
			default:                 strBuffer.Append("Unknown remark");
			}
		}
	}

	public class Remark: this()
	{
		private StringView source;
		public RemarkType RemarkType;
		public String Description ~ delete _;
		public List<TrackPoint> Track ~ delete _;
		public int FinalPos;

		public this(RemarkType remarkType = default, StringView description = default) {
			RemarkType = remarkType;
			Description = new .(description);
		}

		public override void ToString(String strBuffer) {
			strBuffer += scope $"{RemarkType} at {FinalPos}";
			if (!Track.IsEmpty) {
				let last = Track.Back;
				strBuffer += scope:: $" in \"{last.name}\" from {last.pos}";
			}

			if (!Description.IsEmpty)
				strBuffer.Append("\n", Description);
		}

		public bool RemoveOnBacktrack() {
			if (RemarkType case .Other(?, let removeOnBacktrack))
				return removeOnBacktrack;
			return RemarkType != .Error;
		}
	}

	public void AddRemark(RemarkType remarkType, StringView description)
		=> AddRemark(new Remark(remarkType, description));

	public void AddRemark(Remark remark) {
		([Friend]remark.source) = source;
		remark.Track = track.CopyTo(..new List<TrackPoint>(track.Count));
		remarks.Add(remark);
	}

#region Basic parsers
	[Inline] 
	public Parsed<uint8> GetByte() {
		if (pos >= source.Length)
			return ParserErr();
		return Wrap((uint8)source[pos++]);
	}

	[Inline] 
	public Parsed<char32> GetChar() {
		if (pos >= source.Length)
			return ParserErr();

		let res = TrySilent!(UTF8.TryDecode(source.Ptr, source.Length));
		pos += res.1;
		return Wrap(res.0);
	}

	public Parsed<T> GetRaw<T>() where T: ValueType {
		if (sizeof(T) > LengthLeft)
			return ParserErr();
		return Wrap(BitConverter.Convert<uint8[sizeof(T)], T>(getBytes<const sizeof(T)>()));
	}

	public Parsed<T> GetBackwardRaw<T>() where T: ValueType {
		if (LengthLeft >= sizeof(T)) {
			var bytes = getBytes<const sizeof(T)>();
			endianSwap(&bytes, sizeof(T));
			return Wrap(BitConverter.Convert<uint8[sizeof(T)], T>(bytes));
		}

		return ParserErr();
	}

	public Parsed<char32> GetChar(params char32[] allowedChars) {
		Start();
		if (let charA = GetChar().Nullable) {
			for (let charB in allowedChars)
				if (charA == charB)
					return Ok(charA);
		}

		return Err();
	}

	public bool HasByte(uint8 byte) {
		if (let b = GetByte().Nullable)
			return b == byte;
		return false;
	}

	public bool HasChar(char32 char) {
		if (let b = GetChar().Nullable)
			return b == char;
		return false;
	}
	
	public bool HasChar(char8 charB) {
		if (pos < source.Length && source[pos] == charB) {
			pos++;
			return true;
		}
		return false;
	}
	
	public Parsed<char8> GetAsciiChar() {
		if (pos < source.Length) {
			let ch = source[pos];
			if (uint8(ch) < 128) {
				pos++;
				return Wrap(ch);
			}
		}
		return ParserErr();
	}

	public bool HasExactly(StringView substring) {
		if (pos + substring.Length > source.Length)
			return false;

		for (let i < substring.Length) {
			if (substring[i] != source[pos+i])
				return false;
		}

		pos += substring.Length;
		return true;
	}

	private uint8[N] getBytes<N>()
	where N:const int {
		uint8[N] ret = ?;
		let pos_ = pos;
		for (var i = 0; i < N; i++)
			ret[i] = (.)source[pos_ + i];

		pos = pos_ + N;
		return ret;
	}

	//todo: test if this works
	private static void endianSwap(void* ptr, int length) {
		let bytes = (uint8*) ptr;
		for (var i = 0; i <= (length-1)/2; i++)
			Swap!(ref bytes[i], ref bytes[length-1-i]);
	}
#endregion
	
	public static Parsed<T> Wrap<T>(T v)
		=> .() {
			ValueOrDefault = v,
			HasValue = true
		};

	public static ParserErr Err
		=> default;

	//todo: check if works
	public static void LogBytes(String strBuffer, StringView source, int start = 0, int count = int.MaxValue) {
		let finalPos = Math.Min(start + count, source.Length - 1);
		for (int i = start; i <= finalPos; i++) {
			let byte = (uint8) source[i];

			var ch = (char8) byte;
			if (!ch.IsLetterOrDigit)
				ch = '?';

			let digit1 = byte >> 4;
			let digit0 = uint8(byte - (digit1 << 4));
			let d1 = toHexChar(digit1);
			let d0 = toHexChar(digit0);
			strBuffer += scope $"{i}: 0x{d1}{d0}        {byte}='{ch}'\n";
		}
	}

	private static char8 toHexChar(uint digit) {
		if (digit < 10) {
			return '0' + digit;
		} else if (digit < 16) {
			return 'A' + (digit - 10);
		} else {
			return '?';
		}
	}
}