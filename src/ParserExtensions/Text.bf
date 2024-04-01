using System;

namespace Parsive.Text
{
	static
	{
		public static char8? Letter(this Parser p)
		{
			p.Try!();
			if(p.Char().Exists(let ch))
			{
				let i = (int)ch;
				if((i >= 0x0041 && i <= 0x007A)) //latin, cyrillic
					return p.endTry!(ch);
			}
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

		public static char8? Match(this Parser p, char8 char) { //had char16 here before, but it seems to have caused bugs
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

			return p.endTry!(ret? p.rawToken : null);
		}

		public static int? Int(this Parser p) {
			var num = p.Number();
			return num.HasValue? (.)Math.Round(num.Value) : null;
		}
	
		public static StringView? Letters(this Parser p) {
			p.Try!();
			var ret = false;
			while(p.Letter().Exists) { ret = true; }
			return p.endTry!(ret? p.rawToken : null);
		}

		public static StringView? Keyword(this Parser p, StringView name) {
			p.Try!();
			if(p.Match(name).Exists(let word) && !(p.Letter().Exists || p.Digit().Exists || p.Match('_').Exists))
				return p.endTry!(word);
			return p.endTry!();
		}

		public static StringView? QuotedText(this Parser p, char8 quoteChar, params StringView[] ignoredSubstrings){
			p.Try!();
			if(p.Match(quoteChar).Exists)
			{
				while(true)
				{
					if(p.Match(params ignoredSubstrings).Exists) continue;
					if(p.Char().Exists(let ch))
					{
						if(ch == quoteChar)
							return p.endTry!(p.source.Substring(p.lastCheckpoint+1, p.pos - 2 - p.lastCheckpoint));
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

		public static double? Number(this Parser p) {
			p.Try!();
			
			var val = 0.0;
			var isNegative = false, pointEncountered = false;
			var n = 0;

			var unread = true;
			while(true)
			{
				if(unread && p.source[p.pos] == '-')
				{
					isNegative = true;
					p.pos++;
				}

				if(p.Digit().Exists(let digit))
				{
					if(!pointEncountered)
						val = 10.0*val + digit;
					else
						val = val + digit*Math.Pow(10.0, --n);
				}
				else if(p.Match('.').Exists)
				{
					pointEncountered = true;
				}
				else if(unread)
				{
					return p.endTry!();
				}
				else
				{
					return p.endTry!(isNegative? -val:val);
				}
				unread = false;
			}
		}
	}
}