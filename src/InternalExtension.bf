namespace System;

extension Internal
{
	public static T UnsafeEndianSwap<T>(T a)
	{
		const int N = sizeof(T);

		var a;
		var ret = *(uint8[N]*)(&a); 
		for(var i = 0; i <= (N-1)/2; i++)
			Swap!(ret[i], ret[N-1-i]);
		return *(T*)(&ret);
	}
}