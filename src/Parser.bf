using System;
using System.Collections;
namespace Parsive;

public class Parser
{
	public List<String> Errors = new .() ~ DeleteContainerAndItems!(_);

	public StringView source;
	public int pos;
	public List<int> checkpoints = new .() ~ delete _;
	int mSourceLength;
	StringView mDebugName = default;
	int mDebugNamePos = -1;

	public this(StringView raw, int start = 0)
	{
		pos = start;
		source = raw;
		mSourceLength = source.Length;
	}

	public void changeSource(StringView newSource, int start = 0)
	{
		if(newSource != default)
			source = newSource;

		pos = start;
		mDebugName = default;
		mDebugNamePos = -1;
		([Friend]checkpoints).Clear();
		mSourceLength = source.Length;
	}

	[Inline] public int lengthLeft => mSourceLength - pos;
	public int lastCheckpoint { [Inline] get => checkpoints.Back; [Inline] set => checkpoints[checkpoints.Count-1] = value; }
	[Inline] public StringView rawToken => .(source, lastCheckpoint, pos-lastCheckpoint-1);

	public void getDebugInfoForTokenName(out StringView tokenName, out int tokenNamePath) {
		tokenNamePath = -1;
		tokenName = mDebugName;
		if(tokenName == default)
			return;

		for(int i = checkpoints.Count-1; i >= 0; i--)
			if(checkpoints[i] == mDebugNamePos)
				{ tokenNamePath = i; return; }
	}

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

	public mixin addTextError(StringView msg = null)
	{
		getTextDebugInfo(let column, let line);
		getDebugInfoForTokenName(let tokenName, ?);
		var str = new String(msg == default? "Parsing error" : msg);
		let info = tokenName == default? "" : scope $"while reading \"{tokenName}\" ";
		Errors.Add(str..Append(scope $"{info} at line {line}:{column}"));
		null
	}

	public mixin addBinaryError(StringView msg = default)
	{
		getDebugInfoForTokenName(let tokenName, ?);
		var str = new String(msg == default? "Parsing error" : msg);
		let info = tokenName == default? "" : scope $"while reading \"{tokenName}\" ";
		Errors.Add(str..Append(scope $"{info} at byte {pos}"));
		null
	}
		
#region Function syntax
	public mixin Try()
	{
		checkpoints.Add(pos);
	}

	public mixin Try(StringView tokenName)
	{
		checkpoints.Add(pos);
		mDebugName = tokenName;
		mDebugNamePos = pos;
	}

	public mixin endTry()
	{
		pos = checkpoints.PopBack();
		null
	}

	public mixin endTry<T>(T? val) where T: ValueType
	{
		pos = (val == null)? checkpoints.PopBack() : pos;
		val
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
		if(pos >= mSourceLength)
			return null;
		return source[pos++];
	}

	[Inline] 
	public uint8? Byte()
	{
		if(pos >= mSourceLength)
			return null;
		return (.)source[pos++];
	}

	public uint8[N]? Bytes<N>() where N:const int
	{
		if(lengthLeft < N)
			return null;

		uint8[N] ret = ?;
		for(var i = 0; i < N; i++)
			ret[i] = (.)source[pos+i];

		pos += N;
		return ret;
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


	

