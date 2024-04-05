using System;
using System.Collections;
using System.Diagnostics;
using System.Reflection;
namespace Parsive.Binary;

//Supports: two's complement, UTF-8 strings (null-terminated or with (un)typed size bytes)
//todo: length-prefixed lists and strings, enums, classes

public struct BinaryFieldAttribute : Attribute
{
	public enum ValueNum { case LittleEndian = 0; case BigEndian; }
	public ValueNum Value;
	public this(ValueNum value, StringView parserName = default) { Value = value; }
}

//Indicates how reference or enum is serialized
[AttributeUsage(.Field)]
public struct BinaryMultifieldAttribute : Attribute
{
	public enum ValueNum { case Terminator(uint8 terminator); case Length(int size, bool typed); } //case BytePrefixed(uint8 caseID);
	public ValueNum Value;
	public this(ValueNum value) => Value = value;
}

static class Autoparser<T> where T : ValueType
{
	[Comptime]
	static void emit(StringView s) => Compiler.EmitTypeBody(typeof(Autoparser<T>), scope $"{s}\n");
	typealias definition = List<statementNum>;
	const String subName = "sub";
	const String mainName = "ParseBinary";

	private enum statementNum
	{
		case Raw(String code);
		case ItemPreceded(String code);

		public override void ToString(String strBuffer)
		{
			switch(this)
			{
			case .Raw(var code):
				strBuffer.Append(code);

			case .ItemPreceded(var code):
				strBuffer.Append('\t');
				var depth = 0;
				var minDepth = 0;
				for(var i < code.Length)
				{
					if(code[i] == '(') depth++;
					else if(code[i] == ')') depth--;
					minDepth = Math.Min(minDepth, depth);
				}

				for(var i = minDepth; i < 0; i++)
					strBuffer.Append('(');

				strBuffer.Append(code);
			default:
			}
		}

		[Comptime]
		public void PreappendAccessor(StringView scopeName) mut
		{
			if(this case .ItemPreceded(var itemName)) {
				itemName = new $"{scopeName}{itemName}";
				this = .ItemPreceded(itemName);
			}
		}
	}

	//Only for primitive types
	[Comptime]
	static void bitstoreExpr(Type type, bool swap, StringView offsetVar, String strBuffer)
	{
		let size = type.Size;
		let name = type.GetFullName(..scope .());

		if(swap && size > 1)
		{
			strBuffer.Append(scope $"*({name}*)(&char8[{size}](");
			for(var i = size-1; i>=0; i--)
			{
				let id = offsetVar == ""? scope $"{i}" : (i == 0? offsetVar : scope $"{offsetVar}+{i}");
				strBuffer.Append(scope $"source[{id}]");
				if(i > 0) strBuffer.Append(',');
			}
			strBuffer.Append(scope $"))");
		}
		else
		{
			let id = offsetVar == ""? scope $"0" : offsetVar;
			strBuffer.Append(scope $"*({name}*)(&source[{id}])");
		}
	}

	[Comptime]
	static void processField(definition def, Dictionary<Type, definition> allDefs, Type mType, StringView mName, Result<BinaryFieldAttribute> mEndian, Result<BinaryMultifieldAttribute> mOption)
	{
		if(mType.IsPrimitive)
		{
			var mEndian;
			if(mType.Size > 1 && mEndian case .Err) mEndian = .Ok(.(.LittleEndian));

			#if BIGENDIAN
				let swap = mType.Size > 1 && mEndian.Value.Value case .LittleEndian;
			#else		
				let swap = mType.Size > 1 && mEndian.Value.Value case .BigEndian;
			#endif

			def.Add(.ItemPreceded(new $"{mName} = {bitstoreExpr(mType, swap, "p.pos", ..new .())};"));
			def.Add(.Raw(new $"\tp.pos += {mType.Size};"));
			return;
		}

		if((mType.IsValueType || mType.IsSizedArray) && mOption case .Err)
		{
			if(mType.IsStruct)
			{
				let statementStart = def.Count;
				for(let f in mType.GetFields()) processField(def, allDefs, f.FieldType, f.Name, f.GetCustomAttribute<BinaryFieldAttribute>(), f.GetCustomAttribute<BinaryMultifieldAttribute>());
				for(let i in statementStart..<def.Count) def[i].PreappendAccessor(scope $"{mName}.");
			}
			else if(mType.IsSizedArray)
			{
				var arrType = mType as SizedArrayType;
				for(let fId < arrType.ElementCount)
				{
					let statementStart = def.Count;
					processField(def, allDefs, arrType.UnderlyingType, scope $"[{fId}])", mEndian, .Err);
					for(let i in statementStart..<def.Count) def[i].PreappendAccessor(scope $"{mName}");
				}
			}
			else
			{
				Debug.FatalError(scope $"Unsupported value type {mType}");
			}
			return;
		}

		if(mOption case .Err) Debug.FatalError(scope $"Missing BinaryOption attribute for field {mName}");

		if(mOption.Value.Value case .Terminator(let terminator))
		{
			String fTypeName = mType.GetFullName(..scope .());
			Type itemType = null;
			if(fTypeName.StartsWith("System.Collections.List"))
			{
				for(var ff in mType.GetMethods()) if(ff.Name.Contains("Pop")) itemType = ff.ReturnType;
			}
			else
				Debug.FatalError("Field type does not support byte-terminated binary representation");

			let itemTypeName = itemType.GetFullName(..scope .());
			def.Add(.Raw(new $"""
				do
				{'{'}
					let count = source.Length;
					var i = p.pos;
					var terminated = false;
			"""));
			def.Add(.ItemPreceded(new $"{mName} = new List<{itemTypeName}>();"));
			def.Add(.Raw(new $"""
					while(i < count)
					{'{'}
						if({terminator}u == (.)source[i])
						{'{'}
							terminated = true;
							break;
						{'}'}
			"""));

			if(itemType.Size == 1)
			{
				def.Add(.ItemPreceded(new $"{mName}.Add({bitstoreExpr(itemType, false, "i++", ..scope .())});"));
			}
			else
			{
				if(!allDefs.ContainsKey(itemType)) comptimeGenerate(itemType, allDefs, true);

				def.Add(.Raw(new $"""
								{itemTypeName}? v = ?;
								{subName}(p, out v);
								if(!v.HasValue) break;
					"""));
				def.Add(.ItemPreceded(new $"{mName}.Add(v.Value);"));
			}

			def.Add(.Raw(new $"""
					{'}'}
					p.pos = i;
					if(!terminated) p.addBinaryError!("Expected termination byte");
				{'}'}
			"""));
		}
		else if(mOption.Value.Value case .Length(let lengthSize, let lengthTyped))
		{

		}
	}

	[Comptime]
	static int findMinRequiredSize(Type type, out bool _break)
	{
		_break = false;
		if(type.IsPrimitive) { return type.Size; }

		var size = 0;
		for(var f in type.GetFields())
		{
			if(!f.IsInstanceField) continue;
			let fType = f.FieldType;
			
			Result<BinaryMultifieldAttribute> option = f.GetCustomAttribute<BinaryMultifieldAttribute>();
			if((fType.IsValueType || fType.IsSizedArray) && option case .Err)
			{
				if(fType.IsStruct || fType.IsTuple) { size += findMinRequiredSize(fType, out _break); if(_break) return size; }
				else size += fType.Size;
			}
			else
			{
				if(option case .Err) Debug.FatalError(scope $"Instance field {f.Name} is not marked with any serialization attributes");
				if(option.Value.Value case .Length(let oSize, ?)) size += oSize;
				_break = true;
				return size;
			}
		}
		return size;
	}

	[OnCompile(.TypeInit), Comptime]
	static void comptimeGenerateBundle()
	{
		let mainType = typeof(T);
		let mainTypeName = mainType.GetFullName(..scope .());
		if(mainTypeName == "T") { emit(scope $"public static T? {mainName}(Parser p) => null;"); return; }
		
		var defs = new Dictionary<Type, definition>();
		comptimeGenerate(mainType, defs, false);
		emit(scope $"[Inline] public static {mainTypeName}? {mainName}(Parser p) {'{'} {mainTypeName}? v = ?; {subName}(p, out v); return v; {'}'}");
	}

	[Comptime]
	static void comptimeGenerate(Type type, Dictionary<Type, definition> allDefs, bool sub)
	{
		var def = new definition();
		allDefs.Add(type, def);
		let typeName = type.GetFullName(..scope .());
		var minRequiredSize = findMinRequiredSize(type, let sizeIsDynamic);

		def.Add(.Raw(new $"""
		static void {subName}(Parser p, out {typeName}? output)
		{'{'}
			output = null;
		"""));

		if(minRequiredSize > 1)
		{
			def.Add(.Raw(new $"\tif(p.lengthLeft < {minRequiredSize}) if(p.lengthLeft < 1) p.addBinaryError!(\"Not enough binary length\"); return;"));
		}

		def.Add(.Raw(new $"""
			{sizeIsDynamic? "p.Try!();" : ""}
			{typeName} ret = ?;
			let source = p.source;
		"""));

		for(var f in type.GetFields()) processField(def, allDefs, f.FieldType, f.Name, f.GetCustomAttribute<BinaryFieldAttribute>(), f.GetCustomAttribute<BinaryMultifieldAttribute>());

		def.Add(.Raw(new $"""
			output = ret;
			{sizeIsDynamic? "p.endTry!(ret);" : ""}
		{'}'}
		"""));

		for(var st in def)
		{
			st.PreappendAccessor("ret.");
			emit(st.ToString(..scope .()));
		}
	}
}