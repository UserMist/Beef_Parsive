using System;
using System.Collections;
using System.Diagnostics;
using System.Reflection;
namespace Parsive;

//Supports: Beef primitives, UTF-8, arrays, lists
//todo: Universal code (VLQ), enums, classes

public struct BinaryEndianAttribute : Attribute
{
	public enum ValueNum { case Little = 0; case Big; }
	public ValueNum Value;
	public this(ValueNum value, StringView parserName = default) { Value = value; }
}

//Indicates how reference or enum is serialized
[AttributeUsage(.Field)]
public struct BinaryDynamicSizeAttribute : Attribute
{
	public enum ValueNum { case Terminator(uint8 terminator); case Length(int size, bool typed, bool bigEndian); } //case BytePrefixed(uint8 caseID);
	public ValueNum Value;
	public this(ValueNum value)
	{
		Value = value;
		if(value case .Length(let size, ?, ?) && (size > 4 || size < 0))
			Debug.FatalError("Invalid size of length primitive");
	}
}

public static class Autoparser<T> where T : ValueType
{
	[Comptime]
	static void emit(StringView s) => Compiler.EmitTypeBody(typeof(Autoparser<T>), scope $"{s}\n");
	typealias definition = List<statementNum>;
	const String subName = "binarySub";
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
	static void bitstoreExpr(Type type, bool swap, StringView offsetVar, String strBuffer, int sizeOverride = 0)
	{
		let size = sizeOverride == 0? type.Size : sizeOverride;
		let name = type.GetFullName(..scope .());

		if(type.Size == 1 || !swap && size == type.Size)
		{
			let id = offsetVar == ""? scope $"0" : offsetVar;
			strBuffer.Append(scope $"*({name}*)(&source[{id}])");
		}
		else
		{
			strBuffer.Append(scope $"*({name}*)(&char8[{type.Size}](");
			defer strBuffer.Append("))");

			var args = scope $"";
			let dir = swap? -1 : 1;
			let start = swap? size-1 : 0;
			let exclEnd = swap? -1 : size;
			for(var i = start; i != exclEnd; i += dir)
			{
				let id = offsetVar == ""? scope $"{i}" : (i == 0? offsetVar : scope $"{i} + {offsetVar}");
				args.Append(scope $"source[{id}]");
				if(i != exclEnd-dir) args.Append(',');
			}

			#if !BIENDIAN
				strBuffer.Append(args);
				for(var i = size; i < type.Size; i++) strBuffer.Append(",(.)0");
			#else
				for(var i = size; i < type.Size; i++) strBuffer.Append("(.)0,");
				strBuffer.Append(args);
			#endif
		}
	}

	[Comptime]
	static void processField(definition def, Dictionary<Type, definition> allDefs, Type mType, StringView mName, Result<BinaryEndianAttribute> mEndian, Result<BinaryDynamicSizeAttribute> mOption)
	{
		let mTypeName = mType.GetFullName(..scope .());
		if(mType.IsPrimitive)
		{
			var mEndian;
			if(mType.Size > 1 && mEndian case .Err) mEndian = .Ok(.(.Little));

			#if BIGENDIAN
				let swap = mType.Size > 1 && mEndian.Value.Value case .LittleEndian;
			#else		
				let swap = mType.Size > 1 && mEndian.Value.Value case .Big;
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
				for(let f in mType.GetFields()) processField(def, allDefs, f.FieldType, f.Name, f.GetCustomAttribute<BinaryEndianAttribute>(), f.GetCustomAttribute<BinaryDynamicSizeAttribute>());
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

		if(mOption case .Err) Debug.FatalError(scope $"Missing BinaryDynamicField attribute for field {mName}");
		
		Type itemType = null;

		if(mType.IsArray || mTypeName.StartsWith("System.Collections.List"))
			itemType = (mType as SpecializedGenericType).GetGenericArg(0);
		else if(mType == typeof(String))
			itemType = typeof(char8);
		else
			Debug.FatalError("Unsupported type type");
		
		let itemTypeName = itemType.GetFullName(..new .());
		let _append = mType == typeof(String)? "Append" : "Add";

		if(mOption.Value.Value case .Terminator(let terminator))
		{
			if(mType.IsArray) Debug.FatalError(scope $"Field type {mTypeName} does not support byte-terminated binary representation");
			if(mType != typeof(String)) Debug.Write("Terminators are best suited for strings");

			if(mType == typeof(String))
				def.Add(.ItemPreceded(new $"{mName} = new String();"));
			else
				def.Add(.ItemPreceded(new $"{mName} = new List<{itemTypeName}>();"));

			def.Add(.Raw(new $"""
				while(true)
				{'{'}
			"""));

			//loop body
			let _errEoL = "p.addBinaryError!(\"Expected termination byte\");";
			def.Add(.Raw(new $"\t\tif(p.pos >= source.Length || source[p.pos] == (char8){terminator}) {'{'} if(p.pos >= source.Length) {_errEoL} else p.pos++; break; {'}'}"));
			if(itemType.IsPrimitive)
			{
				def.Add(.ItemPreceded(new $"{mName}.{_append}({bitstoreExpr(itemType, false, "p.pos", ..scope .())});"));
				def.Add(.Raw(new $"\t\tp.pos += {itemType.Size};"));
			}
			else
			{
				if(!allDefs.ContainsKey(itemType)) generateParser(itemType, allDefs, true);
				def.Add(.Raw(new $"""
						{itemTypeName}? v = ?;
						{subName}(p, out v);
						if(!v.HasValue) {'{'} {_errEoL} break; {'}'}
				"""));
				def.Add(.ItemPreceded(new $"{mName}.{_append}(v.ValueOrDefault);"));
			}

			def.Add(.Raw(new $"""
				{'}'}
			"""));
		}
		else if(mOption.Value.Value case .Length(let lengthSize, let lengthIsTyped, let lengthIsBigEndian))
		{
			findMinRequiredSize(itemType, let itemIsDynamicSize);
			if(itemIsDynamicSize && mType.IsArray && !lengthIsTyped) Debug.FatalError("Array can't be preallocated in this context. Use something else");
			def.Add(.Raw("\t{"));

			#if BIGENDIAN
				let swap = !lengthIsBigEndian;
			#else		
				let swap = lengthIsBigEndian;
			#endif
			let _store = bitstoreExpr(typeof(int64), swap, "p.pos", ..scope $"", lengthSize);
			let _storedVar = lengthIsTyped? "count" : "totalSize";
			def.Add(.Raw(new $"""
					let {_storedVar} = {_store};
					p.pos += {lengthSize};
			"""));
			
			if(lengthIsTyped && !itemIsDynamicSize)
				def.Add(.Raw(new $"\t\tlet totalSize = count*{itemType.Size};"));

			if(mType.IsArray)
				def.Add(.ItemPreceded(new $"{mName} = new {itemTypeName}[count];"));
			else if(mType == typeof(String))
				def.Add(.ItemPreceded(new $"{mName} = new String({lengthIsTyped? "count" : ""});"));
			else
				def.Add(.ItemPreceded(new $"{mName} = new List<{itemTypeName}>({lengthIsTyped? "count" : ""});"));

			if(itemIsDynamicSize && lengthIsTyped) def.Add(.Raw(new $"\t\tvar i = 0;"));

			if(!itemIsDynamicSize || !lengthIsTyped)
			{
				def.Add(.Raw(new $"""
						let limit = p.pos + totalSize;
				"""));
			}

			def.Add(.Raw(new $"""
					while(true)
					{'{'}
			"""));

			//loop body
			if(!itemIsDynamicSize)
			{
				def.Add(.Raw(new $"\t\t\tif(p.pos >= limit) break;"));

				if(itemType.IsPrimitive)
				{
					if(mType.IsArray)
						def.Add(.ItemPreceded(new $"{mName}[p.pos] = {bitstoreExpr(itemType, false, "p.pos", ..scope .())};"));
					else
						def.Add(.ItemPreceded(new $"{mName}.{_append}({bitstoreExpr(itemType, false, "p.pos", ..scope .())});"));

					def.Add(.Raw(new $"\t\t\tp.pos += {itemType.Size};"));
				}
				else
				{
					if(!allDefs.ContainsKey(itemType)) generateParser(itemType, allDefs, true);
					def.Add(.Raw(new $"""
								{itemTypeName}? v = ?;
								{subName}(p, out v);
								if(!v.HasValue) break;
					"""));
				}
			}
			else
			{
				if(lengthIsTyped)
					def.Add(.Raw(new $"\t\t\tif(i >= count) break;"));
				else
					def.Add(.Raw(new $"\t\t\tif(p.pos >= limit) break;"));

				if(!allDefs.ContainsKey(itemType)) generateParser(itemType, allDefs, true);
				def.Add(.Raw(new $"""
							{itemTypeName}? v = ?;
							{subName}(p, out v);
							if(!v.HasValue) break;
				"""));

				if(mType.IsArray)
					def.Add(.ItemPreceded(new $"{mName}[i] = v.ValueOrDefault;"));
				else
					def.Add(.ItemPreceded(new $"{mName}.Add(v.ValueOrDefault);"));

				if(lengthIsTyped)
					def.Add(.Raw(new $"\t\t\ti++;"));
			}

			def.Add(.Raw(new $"""
					{'}'}
					if(p.pos > source.Length) p.addBinaryError!("Array spanned beyond source end");
				{'}'}
			"""));
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
			
			Result<BinaryDynamicSizeAttribute> option = f.GetCustomAttribute<BinaryDynamicSizeAttribute>();
			if((fType.IsValueType || fType.IsSizedArray) && option case .Err)
			{
				if(fType.IsStruct || fType.IsTuple) { size += findMinRequiredSize(fType, out _break); if(_break) return size; }
				else size += fType.Size;
			}
			else
			{
				if(option case .Err) Debug.FatalError(scope $"Instance field {f.Name} is not marked with any serialization attributes");
				if(option.Value.Value case .Length(let oSize, ?, ?)) size += oSize;
				_break = true;
				return size;
			}
		}
		return size;
	}

	[Comptime]
	static void generateParser(Type type, Dictionary<Type, definition> allDefs, bool sub)
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
			def.Add(.Raw(new $"\tif(p.lengthLeft < {minRequiredSize}) {'{'} if(p.lengthLeft > 0) p.addBinaryError!(\"Unexpected end of source\"); return; {'}'}"));
		}

		let tryArg = type.GetName(..scope .("\""))..Append('"');
		let tryText = sizeIsDynamic? new $"p.Try!({tryArg});" : "";
		def.Add(.Raw(new $"""
			{tryText}
			{typeName} ret = ?;
			let source = p.source;
		"""));

		for(var f in type.GetFields()) processField(def, allDefs, f.FieldType, f.Name, f.GetCustomAttribute<BinaryEndianAttribute>(), f.GetCustomAttribute<BinaryDynamicSizeAttribute>());

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

	[OnCompile(.TypeInit), Comptime]
	static void comptimeInit()
	{
		let mainType = typeof(T);
		let mainTypeName = mainType.GetFullName(..scope .());
		if(mainTypeName == "T") { emit(scope $"public static T? {mainName}(Parser p) => null;"); return; }
		var defs = new Dictionary<Type, definition>();
		generateParser(mainType, defs, false);
		emit(scope $"[Inline] public static {mainTypeName}? {mainName}(Parser p) {'{'} {mainTypeName}? v = ?; {subName}(p, out v); return v; {'}'}");
	}
}