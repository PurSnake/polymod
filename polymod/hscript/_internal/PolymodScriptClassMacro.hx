package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypeParameter;
import polymod.util.MacroUtil;
#end

using StringTools;

/**
 * Provides a macro which, generates implementations of types so that they can be usable by HScript.
 * We have to do weird shenanigans to make them accessible at runtime though.
 */
class PolymodScriptClassMacro
{
  /**
   * The name for the Haxe resource that stores Generation Metadata.
   */
  static inline final METADATA_RESOURCE_NAME:String = 'PolymodScriptClassMacro_METADATA';

  /**
   * @return An expression containing a map of abstract classes to their implementations
   */
  public static macro function listAbstractImpls():ExprOf<Map<String, AbstractImplEntry>>
  {
    if (!onAfterTypingCallbackRegistered)
    {
      onAfterTypingCallbackRegistered = true;
      haxe.macro.Context.onAfterTyping(onAfterTyping);
    }

    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchAbstractImpls();
  }

  /**
   * @return An expression containing a map of each typedef name to
   *  the underlying class type.
   */
  public static macro function listTypedefs():ExprOf<Map<String, Class<Dynamic>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchTypedefs();
  }

  public static macro function listTypeMetadata():ExprOf<Array<Dynamic>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }
    return macro polymod.hscript._internal.ScriptTypeMetadata.fetchTypeMetadata();
  }

  /**
   * @return An expression containing a mapping of each package to what classes are in said package.
   */
  public static macro function listPackagesList():ExprOf<Map<String, Array<String>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchPackagesList();
  }

  /**
   * @return An expression containing a map of each interface package name and the data for it needed for it to be constructed at runtime.
   */
  public static macro function listInterfaceImpls():ExprOf<Map<String, Array<Dynamic>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }
    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchInterfaceImpls();
  }

  /**
   * @return An expression containing a map of each class package and the interfaces it extends.
   * We aren't able to resolve this at runtime so we use a macro.
   */
  public static macro function listClassesExtendingInterfaces():ExprOf<Map<String, Array<String>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }
    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchClassesExtendingInterfaces();
  }


  #if macro
  static var onGenerateCallbackRegistered:Bool = false;
  static var onAfterTypingCallbackRegistered:Bool = false;
  static var packageEntries:Map<String, Array<String>> = [];

  static function onGenerate(allTypes:Array<haxe.macro.Type>)
  {
    packageEntries.clear();

    // Reset these, since onGenerate persists across multiple builds.
    var abstractImplEntries:Array<Array<String>> = [];
    var typedefEntries:Array<Array<String>> = [];
    var interfaces:Map<String, Array<Dynamic>> = [];
    var classesExtendingInterfaces:Map<String, Array<String>> = [];
    var typeEntries:Array<Dynamic> = [];
    var typeNames:Map<String, Bool> = new Map();
    var interfaceCount:Int = 0;

    var startTime:Float = Sys.time();

    for (type in allTypes)
    {
      switch (type)
      {
        case TInst(t, _params):
          var classType:ClassType = t.get();
          switch (classType.kind)
          {
            case KTypeParameter(_), KExpr(_): continue;
            default:
          }
          // Parse classes to check if they are `HScriptedClass` implementations, for processing later.
          var classPack:String = classType.pack.join('.');
          var classPath:String = t.toString();

          if (!typeNames.exists(classPath))
          {
            typeNames.set(classPath, true);
            typeEntries.push(classTypeToMetadata(classPath, classType));
          }

          if (classType.isInterface)
          {
            var interfacePath:String = t.toString();

            if (_params.length > 0) continue;

            var interfaceFields:Array<ClassField> = classType.fields.get();
            var staticFields:Array<ClassField> = classType.statics.get();
            var extend:Array<String> = [for (inter in classType.interfaces) inter.t.toString()];

            // We can't use the typedefs from `Expr` as they throw an error, so we have to define our own info to process later.
            var fieldDecls:Array<InterfaceFieldDecl> = [];

            for (field in interfaceFields)
            {
              if (field.meta.get().length > 0) continue;

              var fieldAccess:Array<String> = [];
              var fieldKind:Null<String> = null;
              var fieldKindParams:Dynamic = null;

              if (field.isPublic)
                fieldAccess.push('public');
              else
                fieldAccess.push('private');

              if (staticFields.contains(field))
                fieldAccess.push('static');

              switch (field.kind)
              {
                case FVar(read, write):
                  var getAccess = fetchVarAccess(read);
                  var setAccess = fetchVarAccess(write);

                  fieldKind = 'var';
                  fieldKindParams = {
                    get: getAccess ?? 'get',
                    set: setAccess ?? 'set',
                    isFinal: field.isFinal,
                  }
                case FMethod(k):
                  if (k != MethNormal) continue;

                  var args:Array<String> = [];
                  switch (field.type)
                  {
                    case TFun(funcArgs, ret):
                      for (arg in funcArgs)
                      {
                        args.push(arg.name);
                      }
                    default:
                  }
                  fieldKind = 'method';
                  fieldKindParams = {
                    args: args,
                  }
              }

              var fieldDecl:InterfaceFieldDecl = {
                name: field.name,
                access: fieldAccess,
                kind: fieldKind,
                kindParams: fieldKindParams,
              }
              fieldDecls.push(fieldDecl);
            }
            interfaceCount++;
            interfaces.set(interfacePath, [fieldDecls, extend]);
          }
          else
          {
            var interfacesImplemented:Array<Ref<ClassType>> = [for (inter in classType.interfaces) inter.t];
            var superCls:ClassType = classType.superClass?.t?.get() ?? null;
            while (superCls != null)
            {
              var superClassInterfaces:Array<Ref<ClassType>> = [for (inter in superCls.interfaces) inter.t];
              interfacesImplemented = interfacesImplemented.concat(superClassInterfaces);

              superCls = superCls.superClass?.t?.get() ?? null;
            }

            // Only append classes that actually implement interfaces.
            if (interfacesImplemented.length > 0)
            {
              // Store all unique interfaces that this class has.
              var extend:Array<String> = [];
              for (implement in interfacesImplemented)
              {
                if (implement.get().params.length > 0) continue;

                var interfacePath:String = implement.toString();

                if (!extend.contains(interfacePath)) extend.push(interfacePath);

                var superInterfaces:Array<String> = MacroUtil.listSuperInterfaces(implement.get());
                for (superInt in superInterfaces)
                {
                  if (!extend.contains(superInt)) extend.push(superInt);
                }
              }
              classesExtendingInterfaces.set(classPath, extend);
            }
          }

          addPackageClass(classPack, classPath);
        case TType(t, _params):
          var typedefPath:String = t.toString();
          if (!typeNames.exists(typedefPath))
          {
            typeNames.set(typedefPath, true);
            var typedefType = t.get();
            typeEntries.push({
              kind: 'typedef',
              name: typedefPath,
              params: [for (param in typedefType.params) scopedParamName(typedefPath, param.name)],
              type: typeToMetadata(typedefType.type, 0, scopedTypeParameters(typedefType.params, typedefPath)),
            });
          }
          var typedefTarget:Type = Context.followWithAbstracts(type);

          switch (typedefTarget)
          {
            case TAnonymous(_):
              // Ignore typedefs to anonymous structures.
              continue;
            case TDynamic(_):
              // Ignore typedefs to Dynamic.
              continue;
            case TFun(_args, _ret):
              // Ignore typedefs to functions.
              continue;

            case TAbstract(t, _params):
              var targetPath:String = t.toString();

              var entryData = [typedefPath, targetPath];

              typedefEntries.push(entryData);
              addPackageClass(t.get().pack.join('.'), targetPath);
            case TEnum(t, _params):
              var targetEnum:EnumType = t.get();
              var targetEnumPath:String = '${targetEnum.pack.concat([targetEnum.name]).join(".")}';

              var entryData = [typedefPath, targetEnumPath];

              typedefEntries.push(entryData);
              addPackageClass(targetEnum.pack.join('.'), targetEnumPath);
            case TInst(t, _params):
              var targetClass:ClassType = t.get();
              var targetClassPath:String = '${targetClass.pack.concat([targetClass.name]).join(".")}';

              var entryData = [typedefPath, targetClassPath];

              typedefEntries.push(entryData);
              addPackageClass(targetClass.pack.join('.'), targetClassPath);
            default:
              // Unknown typedef target type?
              trace('TYPEDEF: ${typedefPath} -> ${typedefTarget}');
          }

        case TAbstract(t, _params):
          // Perform additional processing on abstracts classes to ensure they can be accessed at runtime.

          var abstractPath:String = t.toString();
          var abstractType = t.get();
          var abstractPack:String = abstractType.pack.join('.');
          var abstractImpl = abstractType.impl?.get();

          if (!typeNames.exists(abstractPath))
          {
            typeNames.set(abstractPath, true);
            typeEntries.push(abstractTypeToMetadata(abstractPath, abstractType));
          }

          if (abstractImpl == null)
          {
            // If the abstract doesn't have an implementation, it's usually an extern or something, so we always want to ignore it.
            continue;
          }

          var abstractImplPath:String = abstractType.impl?.toString() ?? '';

          var polymodImplPath:String = 'polymod.hscript._internal._abstract.${abstractPath}_PolymodImpl_';
          var hasPolymodImpl:Bool = false;

          try
          {
            Context.getType(polymodImplPath);
            hasPolymodImpl = true;
          }
          catch (e) {}

          var entryData = [
            abstractPath,
            abstractImplPath,
            hasPolymodImpl ? polymodImplPath : null
          ];

          abstractImplEntries.push(entryData);
          addPackageClass(abstractPack, abstractPath);
        case TEnum(t, _params):
          var enumPath:String = t.toString();
          if (!typeNames.exists(enumPath))
          {
            typeNames.set(enumPath, true);
            var enumType = t.get();
            var constructors:Array<Dynamic> = [];
            for (constructorName in enumType.constructs.keys())
            {
              var constructor = enumType.constructs.get(constructorName).get();
              var args:Array<Dynamic> = [];
              switch (constructor.type)
              {
                case TFun(functionArgs, _):
                  for (arg in functionArgs)
                    args.push({name: arg.name, opt: arg.opt, type: typeToMetadata(arg.t, 0, scopedTypeParameters(enumType.params, enumPath))});
                default:
              }
              constructors.push({name: constructorName, args: args});
            }
            typeEntries.push({
              kind: 'enum',
              name: enumPath,
              params: [for (param in enumType.params) scopedParamName(enumPath, param.name)],
              constructors: constructors,
            });
          }
        default:
          continue;
      }
    }

    var metaData = {
      abstractImpls: abstractImplEntries,
      typedefs: typedefEntries,
      packages: packageEntries,
      interfaceEntries: interfaces,
      extendingInterfaces: classesExtendingInterfaces,
      typeEntries: typeEntries,
    };

    var metaDataHXSF = haxe.Serializer.run(metaData);
    Context.addResource(METADATA_RESOURCE_NAME, haxe.io.Bytes.ofString(metaDataHXSF));

    var endTime:Float = Sys.time();

    var duration:Float = endTime - startTime;

    Context.info('PolymodScriptClassMacro: '
      + 'Registered ${abstractImplEntries.length} abstract impls, '
      + '${typedefEntries.length} typedefs, '
      + '${interfaceCount} interfaces '
      + 'in ${duration} sec.',
      Context.currentPos());
  }

  static function onAfterTyping(types:Array<ModuleType>):Void
  {
    var startTime:Float = Sys.time();

    var count:Int = 0;

    for (type in types)
    {
      var fields:Array<Field> = [];

      switch (type)
      {
        case TAbstract(a):
          var abstractPath = a.toString();
          var abstractType = a.get();

          if (abstractType.impl == null)
          {
            // Only a few classes end up here, generally ones that are implemented directly in code.
            // Includes like StdTypes.Float, StdTypes.Dynamic, StdTypes.Void, cpp.Int16, cpp.SizeT, Class, Enum
            continue;
          }
          else
          {
            var abstractImplType = abstractType.impl.get();
            var abstractImplStatics:Array<ClassField> = abstractImplType.statics.get();

            var isAbstractImplExtern = abstractImplType.isExtern;
            if (isAbstractImplExtern)
            {
              // TODO: abstract externs tend to be problematic and cause lots of build errors,
              // so we just skip them for now. If you can find a fix, feel free.
              continue;
            }

            for (field in abstractImplStatics)
            {
              switch (field.kind)
              {
                case FVar(read, write):
                  var canGet:Bool = read == AccInline || read == AccNormal;
                  if (read == AccCall)
                  {
                    var getter:Null<ClassField> = null;
                    for (f in abstractImplStatics)
                    {
                      if (f.name == 'get_${field.name}')
                      {
                        getter = f;
                        break;
                      }
                    }

                    if (getter == null)
                    {
                      throw 'Getter is null?';
                    }

                    switch (getter.type)
                    {
                      case TFun(args, _):
                        if (args.length != 0) continue;
                      default:
                        throw 'Getter has an unknown type?';
                    }

                    canGet = true;
                  }

                  var canSet:Bool = write == AccNormal;
                  if (write == AccCall)
                  {
                    var setter:Null<ClassField> = null;
                    for (f in abstractImplType.statics.get())
                    {
                      if (f.name == 'set_${field.name}')
                      {
                        setter = f;
                        break;
                      }
                    }

                    if (setter == null)
                    {
                      throw 'Setter is null?';
                    }

                    switch (setter.type)
                    {
                      case TFun(args, _):
                        if (args.length != 1) continue;
                      default:
                        throw 'Setter has an unknown type?';
                    }

                    canSet = true;
                  }

                  if (canGet || canSet)
                  {
                    fields.push(
                      {
                        pos: Context.currentPos(),
                        name: field.name,
                        access: [Access.APublic, Access.AStatic],
                        kind: FProp(canGet ? 'get' : 'never', canSet ? 'set' : 'never', (macro :Dynamic), null)
                      });

                    var fieldExpr:Expr = null;
                    try
                    {
                      // when this fails, this should mean that we are dealing with an enum abstract
                      // so we need to handle it differently
                      var fullPath:String = '${abstractType.module}.${abstractType.name}';
                      Context.getType(fullPath);
                      fieldExpr = Context.parse('${fullPath}.${field.name}', Context.currentPos());
                    }
                    catch (_)
                    {
                      fieldExpr = Context.getTypedExpr(field.expr());
                    }

                    if (canGet)
                    {
                      fields.push(
                        {
                          pos: Context.currentPos(),
                          name: 'get_${field.name}',
                          access: [Access.APublic, Access.AStatic],
                          kind: FFun(
                            {
                              args: [],
                              ret: null,
                              expr: macro
                              {@:privateAccess return ${fieldExpr};}
                            })
                        });
                    }

                    if (canSet)
                    {
                      fields.push(
                        {
                          pos: Context.currentPos(),
                          name: 'set_${field.name}',
                          access: [Access.APublic, Access.AStatic],
                          kind: FFun(
                            {
                              args: [
                                {name: 'value'}],
                              ret: null,
                              expr: macro
                              {@:privateAccess return ${fieldExpr} = value;}
                            })
                        });
                    }
                  }

                case FMethod(k):
                  if (k != MethInline) continue;
                  if (abstractPath.startsWith('cpp')) continue;
                  if (abstractPath.startsWith('hl')) continue;
                  if (abstractPath.startsWith('flixel.graphics.atlas.HashOrArray')) continue; // has to be ragebait
                  if (abstractType.isPrivate) continue;

                  switch (field.type)
                  {
                    case TFun(args, ret):
                      if (args.length == 0 || args[0].name != 'this') continue;

                      var fieldArgs = [for (a in args.slice(1)) {name: a.name, type: null}];

                      var absType = TPath(
                        {
                          pack: abstractType.pack,
                          name: abstractType.module.split('.').pop(),
                          sub: abstractType.name,
                          params: [for (_ in abstractType.params) TPType((macro :Dynamic))]
                        });

                      var isVoid = haxe.macro.TypeTools.toString(ret) == 'Void';
                      var callExprString = '${isVoid ? '' : 'returnValue = '}__typedThis.${field.name}(${[for (a in fieldArgs) a.name].join(', ')})';

                      fields.push(
                        {
                          pos: Context.currentPos(),
                          name: field.name,
                          access: [Access.APublic, Access.AStatic],
                          kind: FFun(
                            {
                              args: [
                                {name: '__interp', type: (macro :polymod.hscript._internal.Interp)},
                                {name: '__expr', type: (macro :polymod.hscript._internal.Expr)},
                                {name: '__this', type: (macro :Dynamic)}
                              ].concat(fieldArgs),
                              ret: (macro :Dynamic),
                              expr: macro
                              {
                                var __typedThis = (__this : $absType); // we do this instead of typing __this in the parameter because of haxe.Rest edge case
                                var returnValue:Dynamic = null;
                                @:privateAccess ${Context.parse(callExprString, Context.currentPos())};
                                @:privateAccess __interp.assignValue(__expr, __typedThis, true);
                                return returnValue;
                              }
                            }),
                          // dont generate warnings for this function
                          meta: [
                            {
                              pos: Context.currentPos(),
                              params: [macro "-WAll"],
                              name: ':haxe.warning'
                            }
                          ]
                        });

                    default:
                      throw 'Method is not a function?';
                  }

                default:
                  continue;
              }
            }

            if (fields.length == 0) continue;

            Context.defineType(
              {
                pos: Context.currentPos(),
                pack: ['polymod', 'hscript', '_internal', '_abstract'].concat(abstractType.pack),
                name: '${abstractType.name}_PolymodImpl_', // we need to give them a different name, because else types with an empty package will not work
                kind: TDClass(null, [], false, false, false),
                fields: fields
              }, 'polymod.hscript._internal.PolymodScriptClassMacro');

            count++;
          }
        default:
          continue;
      }
    }

    var endTime:Float = Sys.time();

    var duration:Float = endTime - startTime;

    if (count > 0)
    {
      Context.info('PolymodScriptClassMacro: Created ${count} custom abstract implementations in ${duration} sec.', Context.currentPos());
    }
  }

  static function addPackageClass(pack:String, cls:String):Void
  {
    if (pack.indexOf('.') == -1) return; // Don't store classes without a package.
    if (pack.startsWith('polymod.')) return; // Exclude polymod classes.
    if (cls.endsWith('_Impl_')) return; // Exclude implementation classes.

    var list:Array<String> = packageEntries.get(pack) ?? [];
    if (!list.contains(cls))
    {
      list.push(cls);
      packageEntries.set(pack, list);
    }
  }

  static function classTypeToMetadata(path:String, cls:ClassType):Dynamic
  {
    var classTypeParams = scopedTypeParameters(cls.params, path);
    var superType:Dynamic = null;
    if (cls.superClass != null)
      superType = typeToMetadata(TInst(cls.superClass.t, cls.superClass.params), 0, classTypeParams);

    var interfaces:Array<Dynamic> = [];
    for (interfaceType in cls.interfaces)
      interfaces.push(typeToMetadata(TInst(interfaceType.t, interfaceType.params), 0, classTypeParams));

    var fields:Array<Dynamic> = [];
    for (field in cls.fields.get())
      if (!hasNoScriptMeta(field)) fields.push(fieldToMetadata(field, cls.params, path));

    var statics:Array<Dynamic> = [];
    for (field in cls.statics.get())
      if (!hasNoScriptMeta(field)) statics.push(fieldToMetadata(field, cls.params, path));

    var constructor:Dynamic = null;
    if (cls.constructor != null && !hasNoScriptMeta(cls.constructor.get()))
      constructor = fieldToMetadata(cls.constructor.get(), cls.params, path);

    return {
      kind: 'class',
      name: path,
      params: [for (param in cls.params) scopedParamName(path, param.name)],
      superType: superType,
      interfaces: interfaces,
      fields: fields,
      statics: statics,
      constructor: constructor,
      isInterface: cls.isInterface,
    };
  }

  static function abstractTypeToMetadata(path:String, abs:AbstractType):Dynamic
  {
    var abstractTypeParams = scopedTypeParameters(abs.params, path);
    var from:Array<Dynamic> = [for (fromType in abs.from) typeToMetadata(fromType.t, 0, abstractTypeParams)];
    var to:Array<Dynamic> = [for (toType in abs.to) typeToMetadata(toType.t, 0, abstractTypeParams)];
    var fields:Array<Dynamic> = [];
    var statics:Array<Dynamic> = [];
    var impl = abs.impl == null ? null : abs.impl.get();
    var fieldOwnerParams = impl == null ? abs.params : abs.params.concat(impl.params);

    if (impl != null)
    {
      for (field in impl.fields.get())
      {
        if (hasNoScriptMeta(field)) continue;
        var metadata = fieldToMetadata(field, fieldOwnerParams, path);
        switch (field.type)
        {
          case TFun(args, ret) if (args.length > 0 && args[0].name == 'this')
            metadata.type = {
              kind: 'function',
              functionArgs: [for (arg in args.slice(1)) {name: arg.name, opt: arg.opt, type: typeToMetadata(arg.t, 0, fieldTypeParameters(field, fieldOwnerParams, path))}],
              ret: typeToMetadata(ret, 0, fieldTypeParameters(field, fieldOwnerParams, path)),
              args: [],
            };
          default:
        }
        fields.push(metadata);
      }

      for (field in impl.statics.get())
        if (!hasNoScriptMeta(field)) statics.push(fieldToMetadata(field, fieldOwnerParams, path));
    }

    return {
      kind: 'abstract',
      name: path,
      params: [for (param in abs.params) scopedParamName(path, param.name)],
      underlying: typeToMetadata(abs.type, 0, abstractTypeParams),
      from: from,
      to: to,
      fields: fields,
      statics: statics,
    };
  }

  static function fieldToMetadata(field:ClassField, ownerParams:Array<TypeParameter> = null, ownerPath:String = ''):Dynamic
  {
    if (ownerParams == null) ownerParams = [];
    var typeParams = fieldTypeParameters(field, ownerParams, ownerPath);
    var canWrite = false;
    switch (field.kind)
    {
      case FVar(_, write):
        canWrite = switch (write)
        {
          case AccNormal, AccCall, AccInline: true;
          default: false;
        }
      default:
    }

    return {
      name: field.name,
      isPublic: field.isPublic,
      canWrite: canWrite,
      complete: !field.name.startsWith('__'),
      params: [for (param in field.params) scopedParamName(ownerPath + '#' + field.name, param.name)],
      type: typeToMetadata(field.type, 0, typeParams),
    };
  }

  static function hasNoScriptMeta(field:ClassField):Bool
  {
    for (meta in field.meta.get())
      if (meta.name == ':noScript') return true;
    return false;
  }

  static function hasOptionalMeta(field:ClassField):Bool
  {
    for (meta in field.meta.get())
      if (meta.name == ':optional') return true;
    return false;
  }

  static inline function scopedParamName(scope:String, name:String):String
  {
    return scope.length == 0 ? name : scope + '#' + name;
  }

  static function scopedTypeParameters(params:Array<TypeParameter>, scope:String):Array<{type:ClassType, name:String}>
  {
    return extendScopedTypeParameters([], params, scope);
  }

  static function extendScopedTypeParameters(existing:Array<{type:ClassType, name:String}>, params:Array<TypeParameter>, scope:String):Array<{type:ClassType, name:String}>
  {
    var result = existing.copy();
    for (param in params)
      switch (param.t)
      {
        case TInst(ref, _):
          result.push({type: ref.get(), name: scopedParamName(scope, param.name)});
        default:
      }
    return result;
  }

  static function fieldTypeParameters(field:ClassField, ownerParams:Array<TypeParameter>, ownerPath:String):Array<{type:ClassType, name:String}>
  {
    var result = scopedTypeParameters(ownerParams, ownerPath);
    return extendScopedTypeParameters(result, field.params, ownerPath + '#' + field.name);
  }

  static function typeToMetadata(type:Type, depth:Int = 0, typeParams:Array<{type:ClassType, name:String}> = null):Dynamic
  {
    if (depth > 32) return {kind: 'dynamic'};
    if (typeParams == null) typeParams = [];

    return switch (type)
    {
      case TMono(_), TDynamic(_): {kind: 'dynamic'};
      case TInst(ref, args):
        var classType = ref.get();
        switch (classType.kind)
        {
          case KTypeParameter(_):
            var paramName = classType.name;
            for (parameter in typeParams)
              if (parameter.type == classType)
              {
                paramName = parameter.name;
                break;
              }
            {kind: 'param', name: paramName};
          case KExpr(_): {kind: 'dynamic'};
          default:
            var name = ref.toString();
            {kind: 'class', name: name, args: [for (arg in args) typeToMetadata(arg, depth + 1, typeParams)]};
        }
      case TEnum(ref, args):
        {kind: 'enum', name: ref.toString(), args: [for (arg in args) typeToMetadata(arg, depth + 1, typeParams)]};
      case TType(ref, args):
        {kind: 'typedef', name: ref.toString(), args: [for (arg in args) typeToMetadata(arg, depth + 1, typeParams)]};
      case TAbstract(ref, args):
        var name = ref.toString();
        var shortName = name.split('.').pop();
        if (['Int', 'Float', 'Bool', 'Void'].contains(name)
          || (name.startsWith('StdTypes.') && ['Int', 'Float', 'Bool', 'Void'].contains(shortName)))
          {kind: 'primitive', name: shortName}
        else if (name == 'Null' || name == 'StdTypes.Null')
          {kind: 'null', name: 'Null', args: args.length == 0 ? [{kind: 'dynamic'}] : [for (arg in args) typeToMetadata(arg, depth + 1, typeParams)]}
        else
          {kind: 'abstract', name: name, args: [for (arg in args) typeToMetadata(arg, depth + 1, typeParams)]};
      case TFun(args, ret):
        {
          kind: 'function',
          args: [],
          functionArgs: [for (arg in args) {name: arg.name, opt: arg.opt, type: typeToMetadata(arg.t, depth + 1, typeParams)}],
          ret: typeToMetadata(ret, depth + 1, typeParams),
        };
      case TAnonymous(anon):
        {
          kind: 'anonymous',
          fields: [for (field in anon.get().fields) if (!hasNoScriptMeta(field))
            {
              name: field.name,
              opt: hasOptionalMeta(field),
              type: typeToMetadata(field.type, depth + 1, typeParams),
            }],
        };
      case TLazy(lazy): typeToMetadata(lazy(), depth + 1, typeParams);
      default: {kind: 'dynamic'};
    }
  }

  static function fetchVarAccess(access:haxe.macro.Type.VarAccess):Null<String>
  {
    return switch (access)
    {
      case AccNormal: 'default';
      case AccNo: 'null';
      case AccNever: 'never';
      default: null;
    }
  }
  #end

  static var _metadata:Dynamic = null;

  static function fetchMetadata():Dynamic
  {
    if (_metadata != null) return _metadata;

    var metaDataHXSF:String = haxe.Resource.getString(METADATA_RESOURCE_NAME);
    _metadata = haxe.Unserializer.run(metaDataHXSF);
    return _metadata;
  }


  public static function fetchAbstractImpls():Map<String, AbstractImplEntry>
  {
    var metaData = fetchMetadata();

    if (metaData.abstractImpls != null)
    {
      var result:Map<String, AbstractImplEntry> = [];

      // Each element is formatted as `[abstractPath, abstractImplPath, ?abstractPolymodImplPath]`.

      var abstractImpls:Array<Array<String>> = cast metaData.abstractImpls;
      for (element in abstractImpls)
      {
        if (element.length != 3)
        {
          throw 'Malformed element in abstractImpls: ' + element;
        }

        var abstractPath:String = element[0];
        var abstractImplPath:String = element[1];
        var abstractPolymodImplPath:Null<String> = element[2];
        #if js
        var abstractImplType:Null<Class<Dynamic>> = resolveClass(abstractPath);
        #else
        var abstractImplType:Null<Class<Dynamic>> = cast Type.resolveClass(abstractImplPath);
        #end

        if (abstractImplType == null)
        {
          // If the abstract type was found at compile time, but couldn't resolve at runtime,
          // it probably got optimized out.
          // We'll have to construct a PolymodStaticAbstractReference for it later.
        }

        var abstractPolymodImplType:Null<Class<Dynamic>> = null;

        if (abstractPolymodImplPath != null)
        {
          abstractPolymodImplType = cast Type.resolveClass(abstractPolymodImplPath);
        }

        result.set(abstractPath,
          {
            cls: abstractImplType,
            polymodCls: abstractPolymodImplType
          });
      }

      return result;
    }
    else
    {
      throw 'No abstractImpls found in PolymodScriptClassMacro!';
    }
  }

  public static function fetchTypedefs():Map<String, Class<Dynamic>>
  {
    var metaData = fetchMetadata();

    if (metaData.typedefs != null)
    {
      var result:Map<String, Class<Dynamic>> = [];

      var typedefs:Array<Array<String>> = cast metaData.typedefs;
      for (element in typedefs)
      {
        if (element.length != 2)
        {
          throw 'Malformed element in typedefs: ' + element;
        }

        var fieldPath:String = element[0];
        var reflectClassPath:String = element[1];
        var reflectClass:Class<Dynamic> = cast Type.resolveClass(reflectClassPath);

        result.set(fieldPath, reflectClass);
      }

      return result;
    }
    else
    {
      throw 'No typedefs found in PolymodScriptClassMacro!';
    }
  }

  public static function fetchPackagesList():Map<String, Array<String>>
  {
    var metaData = fetchMetadata();

    if (metaData.packages != null)
    {
      return metaData.packages;
    }
    return [];
  }

  public static function fetchInterfaceImpls():Map<String, Array<Dynamic>>
  {
    var metadata = fetchMetadata();

    return metadata.interfaceEntries;
  }

  public static function fetchClassesExtendingInterfaces():Map<String, Array<String>>
  {
    var metadata = fetchMetadata();

    return metadata.extendingInterfaces;
  }

  #if js
  static var PACKAGE_NAME_INVALID = ~/[^.a-zA-Z0-9]/;

  // Fucked up workaround, volatile and could break at any moment.
  static function resolveClass(clsName:String):Class<Dynamic>
  {
    // Sanitize just in case someone tries to exploit this.
    var sanitizedName = PACKAGE_NAME_INVALID.replace(clsName, '');
    var parsedName = StringTools.replace(sanitizedName, '.', '_');
    try
    {
      return js.Syntax.code('eval({0})', parsedName);
    }
    catch (e)
    {
      return null;
    }
  }
  #end
}

typedef AbstractImplEntry =
{
  cls:Class<Dynamic>,
  polymodCls:Null<Class<Dynamic>>,
};


typedef InterfaceFieldDecl =
{
  var name:String;
  var access:Array<String>;
  var kind:String;
  var kindParams:Dynamic;
}
