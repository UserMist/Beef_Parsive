using System;
using System.Collections;
using System.Reflection;
namespace Parsive.Binary;

public static
{
	private static char8 toHexChar(uint digit) {
		switch(digit) {
			case 0:  return '0';
			case 1:  return '1';
			case 2:  return '2';
			case 3:  return '3';
			case 4:  return '4';
			case 5:  return '5';
			case 6:  return '6';
			case 7:  return '7';
			case 8:  return '8';
			case 9:  return '9';
			case 10: return 'A';
			case 11: return 'B';
			case 12: return 'C';
			case 13: return 'D';
			case 14: return 'E';
			case 15: return 'F';
			default: return '?';
		}
	}

	public static void debugBytes(this Parser p, String strBuffer, int start = 0, int count = int.MaxValue)
	{
		let src = p.source;
		let exclusiveEnd = Math.Min(start+count+1, src.Length);
		for(int i = start; i < exclusiveEnd; i++) {
			var chID = (int)src[i];
			if(!(0x0041 <= chID && chID <= 0x005A || 0x0061 <= chID && chID <= 0x007A))
				chID = 0x0020;

			let ch = (char8)chID;
			let byte = (uint)src[i];
			let digit1 = byte >> 4;
			let digit0 = byte - (digit1 << 4);
			strBuffer.Append(scope $"[{i}]0x{toHexChar(digit1)}{toHexChar(digit0)}        (\'{ch}\':{byte})\n");
		}
	}

	///Parse binary of a primitive type as big endian
	public static T? BigEndian<T>(this Parser p) where T : ValueType
	{
		var bytes = p.Bytes<const sizeof(T)>();
		#if !BIGENDIAN
			bytes = Internal.UnsafeEndianSwap(bytes);
		#endif
		return BitConverter.Convert<uint8[sizeof(T)]?, T?>(bytes);
	}

	///Parse binary of a primitive type as little endian
	public static T? LittleEndian<T>(this Parser p) where T : ValueType
	{
		var bytes = p.Bytes<const sizeof(T)>();
		#if BIGENDIAN
			bytes = Internal.UnsafeEndianSwap(bytes);
		#endif
		return BitConverter.Convert<uint8[sizeof(T)]?, T?>(bytes);
	}

	public static Span<uint8>? ByteTerminatedBytes(this Parser p, uint8 byte) {
		let count = p.source.Length;
		let source = p.source;
		for(var i = p.pos; i < count; i++)
		{
			if(byte == (.)source[i])
			{
				let start = p.pos;
				p.pos = i;
				return .((.)&source[start], p.pos-start);
			}
		}

		p.addBinaryError!("Expected termination byte");
		return null;
	}

	public static Span<uint8>? LengthPrefixedBytes<LengthT, LengthIsBigEndian>(this Parser p) where LengthT : ValueType, var where LengthIsBigEndian : const bool
	{
		let length = LengthIsBigEndian? p.BigEndian<LengthT>() : p.LittleEndian<LengthT>();
		if(length == null) return null;
		let start = p.pos;
		p.pos += (.)length;
		return .((.)&p.source[start], p.pos-start);
	}

	///Read struct binary as is (use BigEndian<T> and LittleEndian<T> fields to specialize their memory layout)
	/*
	public static T? BinaryStruct<T>(this Parser p) where T : struct
	{
		AutoParsing<T>;
	}
	*/

	/*
	public static Parsed<String> ByteStringASCII(this Parser a, String s, int count) {
		Parser.attempt!(a,"ASCII");

		//Result<uint8> byte;
		int i = 0;
		String tempS = scope .();

		for(; i < count && a.nextChar().isTrue(let ch); i++)
			tempS.Append(ch);

		if(i == count) {
			s.Append(tempS);
			return .Ok(s);
		}

		return a.endAttempt();
	}
*/


}
