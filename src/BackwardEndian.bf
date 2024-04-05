namespace System;

#if BIGENDIAN
typealias BigEndian<T> = T;
typealias LittleEndian<T> = Backward<T>;
#else
typealias BigEndian<T> = BackwardEndian<T>;
typealias LittleEndian<T> = T;
#endif

public struct BackwardEndian<T> where T : ValueType
{
	T mRawValue;
	public T Value
	{
		[Inline] get => Internal.UnsafeEndianSwap(mRawValue);
		[Inline] set mut => mRawValue = Internal.UnsafeEndianSwap(value);
	}
	public this(T value) { this = ?; Value = value; }
	public static Self operator implicit(T v) => .(v);
	public static T operator implicit(Self v) => v.Value;
}