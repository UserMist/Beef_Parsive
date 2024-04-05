using System;
namespace Parsive.Text;
public static
{
	public static char8? LetterASCII(this Parser p)
	{
		p.Try!();
		if(p.Char().Exists(let ch) && ch.IsLetter)
			return p.endTry!(ch);
		return p.endTry!();
	}

	public static int? Digit(this Parser p) {
		if(p.Char().Exists(let ch)) switch(ch)
		{
			case '0': return 0;
			case '1': return 1;
			case '2': return 2;
			case '3': return 3;
			case '4': return 4;
			case '5': return 5;
			case '6': return 6;
			case '7': return 7;
			case '8': return 8;
			case '9': return 9;
		}
		return null;
	}

	public static char8? Match(this Parser p, char8 char)
	{
		if(p.Char().Exists(let ch) && ch == char)
			return char;
		return null;
	}

	public static StringView? Spacing(this Parser p)
	{
		p.Try!();

		var ret = false;
		while(p.CharFrom(" \t").Exists)
			ret = true;

		return p.endTry!(ret? p.rawToken : (StringView?)null);
	}
	
	public static StringView? LettersASCII(this Parser p)
	{
		p.Try!();
		var read = false;
		while(p.LetterASCII().Exists) { read = true; }
		return p.endTry!(read? p.rawToken : (StringView?)null);
	}

	public static StringView? Keyword(this Parser p, StringView name)
	{
		p.Try!();
		if(p.Match(name).Exists(let word) && !(p.LetterASCII().Exists || p.Digit().Exists || p.Match('_').Exists))
			return p.endTry!(word);
		return p.endTry!();
	}

	public static StringView? QuotedText(this Parser p, StringView quoteSymbol, StringView ignoredSymbol = "", bool singleLine = false)
	{
		p.Try!();
		if(p.Match(quoteSymbol).Exists)
		{
			while(true)
			{
				if(ignoredSymbol.Length > 0 && p.Match(ignoredSymbol).Exists) continue;
				if(p.Char().Exists(let ch))
				{
					if(p.Match(quoteSymbol).Exists)
						return p.endTry!(p.source.Substring(p.lastCheckpoint + quoteSymbol.Length, p.pos - 1 - quoteSymbol.Length - p.lastCheckpoint));
					else if(singleLine && ch == '\n')
						p.endTry!((StringView?)p.addTextError!("This quotation type is not suitable for multiple lines"));
				}
				else
				{
					p.addTextError!("Quotation did not end");
					return p.endTry!();
				}
			}
		}
		return p.endTry!();
	}

	public static int64? Int64(this Parser p) {
		p.Try!();
			
		int64 val = 0;
		var isNegative = false;
		var unread = true;
		while(true)
		{
			if(unread && (p.source[p.pos] == '-' || p.source[p.pos] == '+'))
				isNegative = (p.source[p.pos++] == '-');

			if(p.Digit().Exists(let digit))
			{
				int64 newVal = ?;
				if(isNegative)
				{
					newVal = 10*val - digit;
					if(newVal > val) p.addTextError!("Number is outside int64 range");
				}
				else
				{
					newVal = 10*val + digit;
					if(newVal < val) p.addTextError!("Number is outside int64 range");
				}

				val = newVal;
			}
			else if(unread)
			{
				return p.endTry!();
			}
			else
			{
				return p.endTry!(val);
			}
			unread = false;
		}
	}

	public static double? Number(this Parser p) {
		p.Try!();
		
		var isNegative = false, unread = true;
		var postPointPos = 0;
		double val = 0;
		while(true)
		{
			if(unread && (p.source[p.pos] == '-' || p.source[p.pos] == '+'))
				isNegative = (p.source[p.pos++] == '-');

			if(p.Digit().Exists(let digit))
			{
				if(postPointPos == 0)
					val = 10*val + digit;
				else
					val = val + digit*Math.Pow(10.0, postPointPos--);
			}
			else if(postPointPos == 0 && p.Match('.').Exists)
				postPointPos = -1;
			else if(unread)
				return p.endTry!();
			else
				return p.endTry!(isNegative? -val:val);

			unread = false;
		}
	}
}
