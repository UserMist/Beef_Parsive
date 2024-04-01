namespace System;
extension Nullable<T>
{
	[Inline] public bool Regardless => true;
	[Inline] public bool Exists => HasValue;
	[Inline]
	public bool Exists(out T res)
	{
		T v = ?;
		if(TryGetValue(ref v)) { res = v; return true; }
		res = default; return false;
	}
}
