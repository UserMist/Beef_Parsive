using System;
namespace Parsive;

public struct ParsedNothing { }

//exists to provide safety for backtrack
public struct Parsed<T>
{
	public T ValueOrDefault;
	public bool HasValue;

	public static implicit operator Parsed<T>(ParsedNothing arg)
		=> default;
}

extension Parsed<T> where T: ValueType
{
	public static implicit operator Nullable<T>(Parsed<T> arg) {
		Nullable<T> ret = ?;
		ret.[Friend]mValue = arg.ValueOrDefault;
		ret.[Friend]mHasValue = arg.HasValue;
		return ret;
	}

	public Nullable<T> Nullable
		=> this;
}

extension Parsed<T> where T: class
{
	public static implicit operator T(Parsed<T> arg)
		=> arg.HasValue? arg.ValueOrDefault : null;

	public T Nullable
		=> this;
}