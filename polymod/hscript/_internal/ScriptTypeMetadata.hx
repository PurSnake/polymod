package polymod.hscript._internal;

@:keep
class ScriptTypeMetadata
{
  static inline final RESOURCE_NAME:String = 'PolymodScriptClassMacro_METADATA';

  static var loaded:Bool = false;
  static var cached:Array<ScriptTypeMetadataEntry> = [];

  @:keep
  public static function fetchTypeMetadata():Array<ScriptTypeMetadataEntry>
  {
    if (loaded) return cached;

    var serialized = haxe.Resource.getString(RESOURCE_NAME);
    if (
      serialized == null
      || serialized.length == 0
    ) throw 'Missing Haxe resource "$RESOURCE_NAME". Ensure PolymodScriptClassMacro metadata generation is enabled.';

    var raw:ScriptTypeMetadataResource = cast haxe.Unserializer.run(serialized);
    if (raw == null || raw.typeEntries == null) throw 'Haxe resource "$RESOURCE_NAME" does not contain typeEntries.';

    cached = raw.typeEntries;
    loaded = true;
    return cached;
  }
}

typedef ScriptTypeMetadataResource =
{
  var ?typeEntries:Array<ScriptTypeMetadataEntry>;
}

typedef ScriptTypeMetadataEntry =
{
  var ?kind:String;
  var ?name:String;
  var ?params:Array<String>;
  var ?superType:ScriptTypeMetadataType;
  var ?isInterface:Bool;
  var ?interfaces:Array<ScriptTypeMetadataType>;
  var ?fields:Array<ScriptTypeMetadataField>;
  var ?statics:Array<ScriptTypeMetadataField>;
  var ?constructor:ScriptTypeMetadataField;
  var ?constructors:Array<ScriptTypeMetadataEnumConstructor>;
  var ?type:ScriptTypeMetadataType;
  var ?underlying:ScriptTypeMetadataType;
  var ?from:Array<ScriptTypeMetadataType>;
  var ?to:Array<ScriptTypeMetadataType>;
}

typedef ScriptTypeMetadataField =
{
  var ?name:String;
  var ?type:ScriptTypeMetadataType;
  var ?isPublic:Bool;
  var ?canWrite:Bool;
  var ?complete:Bool;
  var ?params:Array<String>;
}

typedef ScriptTypeMetadataEnumConstructor =
{
  var ?name:String;
  var ?args:Array<ScriptTypeMetadataFunctionArg>;
}

typedef ScriptTypeMetadataFunctionArg =
{
  var ?name:String;
  var ?opt:Bool;
  var ?type:ScriptTypeMetadataType;
}

typedef ScriptTypeMetadataAnonymousField =
{
  var ?name:String;
  var ?opt:Bool;
  var ?type:ScriptTypeMetadataType;
}

typedef ScriptTypeMetadataType =
{
  var ?kind:String;
  var ?name:String;
  var ?args:Array<ScriptTypeMetadataType>;
  var ?functionArgs:Array<ScriptTypeMetadataFunctionArg>;
  var ?ret:ScriptTypeMetadataType;
  var ?fields:Array<ScriptTypeMetadataAnonymousField>;
}
