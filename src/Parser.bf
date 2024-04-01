using System;
using System.Collections;
namespace Parsive;

public class Parser
{
	public StringView source;
	public int pos;
	public List<int> checkpoints = new .() ~ delete _;
	public List<String> errors = new .() ~ DeleteContainerAndItems!(_);

	public this(StringView raw, int id = 0)
	{
		pos = id;
		source = raw;
	}

	public void changeSource(StringView newSource = default)
	{
		if(newSource != default)
			source = newSource;

		pos = 0;
		([Friend]checkpoints).Clear();
	}

	public int lastCheckpoint { get => checkpoints.Back; set => checkpoints[checkpoints.Count-1] = value; }
	public StringView rawToken => .(source, lastCheckpoint, pos-lastCheckpoint);

	public void getTextDebugInfo(out int column, out int line)
	{
		column = 1;
		line = 1;

		var i = pos-1;
		while(i >= 0)
		{
			if(source[i] == '\n')
			{
				line++;
				break;
			}
			column++;
			i--;
		}

		while(i >= 0) {
			if(source[i] == '\n')
				line++;
			i--;
		}
	}

	public mixin addTextError(String unownedString = null)
	{
		getTextDebugInfo(let column, let line);
		var str = unownedString == null ? new String("Parsing error") : unownedString;
		if(!unownedString.IsDynAlloc) str = new String(unownedString);
		errors.Add(str..Append(scope $" at Line {line} (Column {column})"));
		null
	}

	public mixin addByteError(String unownedString = null)
	{
		var str = unownedString == null ? new String("Parsing error") : unownedString;
		if(!unownedString.IsDynAlloc) str = new String(unownedString);
		errors.Add(str..Append(scope $" at Byte {pos}"));
		null
	}
		
#region Function syntax
	public mixin Try()
	{
		checkpoints.Add(pos);
	}

	public mixin endTry()
	{
		checkpoints.PopBack();
		null
	}

	public mixin endTry<T>(T? res) where T: ValueType
	{
		if(res == null) pos = lastCheckpoint;
		checkpoints.PopBack();
		res
	}

	public mixin endTry<T>(T val)
	{
		checkpoints.PopBack();
		val
	}
#endregion
		
#region Do syntax
	public mixin require(bool r) { if(!r) break; }
	public mixin require<T>(T r) where T:var { if(r == null) break; r }
	public mixin require<T>(T r, out T v) where T:var { v = ?; if(r == null) break; v = r.Value; }
#endregion

	[Inline] 
	public char8? Char()
	{
		if(pos >= source.Length)
			return null;
		return source[pos++];
	}

	[Inline] 
	public uint8? Byte()
	{
		if(pos >= source.Length)
			return null;
		return (.)source[pos++];
	}

	public char8? CharFrom(StringView allowedChars)
	{
		Try!();
		if(Char().Exists(let charA))
			for(let charB in allowedChars)
				if(charA == charB)
					return endTry!(charA);
		return endTry!();
	}

	public char8? Match(char8 charB)
	{
		Try!();
		if(Char().Exists(let charA))
			if(charA == charB)
				return endTry!(charA);
		return endTry!();
	}

	public StringView? Match(StringView substring)
	{
		Try!();
		for(int i < substring.Length)
			if(!Match(substring[i]).Exists)
				return endTry!(); 
		return endTry!(rawToken);
	}

	public StringView? Match(params StringView[] allowedSubstrings)
	{
		Try!();
		for(let substring in allowedSubstrings)
			if(Match(substring) != null)
				return endTry!(substring);
		return endTry!();
	}
}


	

