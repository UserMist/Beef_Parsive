using System;
using System.Collections;
using System.Text;
using System.Diagnostics;
namespace Parsive;

//exists to provide safety for backtrack
public struct Parsed<T> {
	public bool HasValue = false;
	public T ValueOrDefault = default;
}

//Holds onto info used by top-down backtracked parsers of byte arrays
public class ParserData
{
	public StringView source;
	public int        pos;
	public List<int>  backtrack;
	public Tracer     tracer;

	public ~this() {
		Debug.Assert(backtrack.Count == 0);
		Debug.Assert(tracer.stackTrace.Count == 0);
		delete backtrack;
		tracer.Dispose();
	}
	
	[Inline] public StringView RawSymbol
		=> source[backtrack.Back..<pos];

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
		backtrack = new .(8);
		tracer = .(new .(8), new .(16));
	}

	public void FullReset(StringView newSource, int start = 0) {
		if (newSource != default)
			source = newSource;

		pos = start;
		backtrack.Clear();
		tracer.Clear();
	}
	
	public mixin Start() {
		backtrack.Add(pos);
	}

	public mixin Cancel() {
		pos = backtrack.PopBack();
		null
	}

	public mixin Finish(var v) {
		backtrack.PopBack();
		v
	}

	public mixin Finish() {
		backtrack.PopBack();
	}

	public mixin TraceScope(StringView name) {
		TraceStart(name); defer TraceEnd(name);
	}

	public void TraceStart(StringView name) {
		tracer.stackTrace.Add(.(name, pos));
	}

	public void TraceEnd(StringView name) {
		let pop = tracer.stackTrace.PopBack();
		System.Diagnostics.Debug.Assert(pop.name == name);
	}

#region Parsing analytics
	public struct Tracer: this(List<Tracer.Element> stackTrace, List<Remark> remarks), IDisposable
	{
		public struct Element: this(StringView name, int pos);

		public void Clear() {
			ClearAndDeleteItems!(remarks);
			stackTrace.Clear();
		}

		public void Dispose() {
			DeleteContainerAndItems!(remarks);
			delete stackTrace;
		}
	}

	public enum RemarkType
	{
		case Other = default;
		case SymbolRange; //for syntax highlighters
		case Error; //parsing fatally failed
		case SoftError; //parsing partially failed
		case Warning; //parsing didn't fail at all, even though input was wrong/deprecated
		case Suggestion; //parsing didn't fail at all, but input could be prettier
	}

	public class Remark: this()
	{
		private StringView source;
		public String RemarkType ~ delete _;
		public String Description ~ delete _;
		public List<Tracer.Element> StackTrace ~ delete _;
		public int FinalPos;

		public this(StringView remarkType = default, StringView description = default) {
			RemarkType = new .(remarkType);
			Description = new .(description);
		}

		public override void ToString(String strBuffer) {
			if (!RemarkType.IsEmpty) {
				strBuffer += RemarkType;
			} else {
				strBuffer += "Unknown remark";
			}

			strBuffer += scope $" at {FinalPos}";
			if (!StackTrace.IsEmpty) {
				let last = StackTrace.Back;
				strBuffer += scope:: $" in \"{last.name}\" from {last.pos}";
			}

			if (!Description.IsEmpty)
				strBuffer.Append("\n", Description);
		}
	}


	public void AddRemark(RemarkType remarkType, StringView description) {
		switch (remarkType) {
		case .Other:       AddRemark(new Remark("", description));
		case .SymbolRange: AddRemark(new Remark("SymbolRange", description));
		case .Error:       AddRemark(new Remark("Error", description));
		case .SoftError:   AddRemark(new Remark("SoftError", description));
		case .Warning:     AddRemark(new Remark("Warning", description));
		case .Suggestion:  AddRemark(new Remark("Suggestion", description));
		default: ThrowUnimplemented();
		}
		if (!tracer.stackTrace.IsEmpty)
			tracer.stackTrace.PopBack();
	}

	public void AddRemark(Remark remark) {
		([Friend]remark.source) = source;
		remark.StackTrace = tracer.stackTrace.CopyTo(..new List<Tracer.Element>(tracer.stackTrace.Count));
		tracer.remarks.Add(remark);
	}

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
#endregion
		
	[Inline] 
	public uint8? GetByte() {
		if (pos >= source.Length)
			return null;
		return (.)source[pos++];
	}

	[Inline] 
	public char32? GetChar() {
		if (pos >= source.Length)
			return null;

		let res = TrySilent!(UTF8.TryDecode(source.Ptr, source.Length));
		pos += res.1;
		return res.0;
	}

	public T? GetRaw<T>() where T: ValueType {
		if (LengthLeft >= sizeof(T))
			return BitConverter.Convert<uint8[sizeof(T)], T>(getBytes<const sizeof(T)>());
		return null;
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

	public T? GetBackwardRaw<T>() where T: ValueType {
		if (LengthLeft >= sizeof(T)) {
			var bytes = getBytes<const sizeof(T)>();
			endianSwap(&bytes, sizeof(T));
			return BitConverter.Convert<uint8[sizeof(T)], T>(bytes);
		}

		return null;
	}

	//todo: test if this works
	private static void endianSwap(void* ptr, int length) {
		let bytes = (uint8*) ptr;
		for (var i = 0; i <= (length-1)/2; i++)
			Swap!(ref bytes[i], ref bytes[length-1-i]);
	}

	public char32? GetChar(params char32[] allowedChars) {
		Start!();
		if (let charA = GetChar()) {
			for (let charB in allowedChars)
				if (charA == charB)
					return Finish!(charA);
		}

		return Cancel!();
	}

	public bool HasByte(uint8 byte) {
		if (let b = GetByte())
			return b == byte;
		return false;
	}

	public bool HasChar(char32 char) {
		if (let b = GetChar())
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
	
	public char8? GetAsciiChar() {
		if (pos < source.Length) {
			let ch = source[pos];
			if (uint8(ch) < 128) {
				pos++;
				return ch;
			}
		}
		return null;
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
}