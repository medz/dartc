import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'numeric_order.dart';

ByteData _nativeData(ffi.Pointer<ffi.NativeType> pointer, int bytes) =>
    ByteData.sublistView(
      ffi.Uint8Pointer(pointer.cast<ffi.Uint8>()).asTypedList(bytes),
    );

final class IrInterpreter(
  final IrProgram program,
  final Map<(Uri, String), Object? Function(int)> imports, {
  final Object? Function(NativeCall, int, List<Object?>)? callNative,
}) {
  final _loadedLibraries = <DeferredImport>{};
  final _globals = <GlobalVariable, Object?>{
    for (final global in program.globals)
      if (!global.isLate && global.initializer == null) global: null,
  };

  Object? _loadGlobal(GlobalVariable global) {
    if (_globals.containsKey(global)) return _globals[global];
    final initializer = global.initializer;
    if (initializer == null) return _LateRead().value;
    // No busy state: recursive reads may initialize the slot, and exceptions
    // preserve any writes made by the initializer instead of rolling them back.
    final value = _typeOperation(
      global.type,
      _enter(initializer, const []),
      cast: true,
    );
    return _bindLazy(_globals, global, value, isFinal: global.isFinal);
  }

  void _storeGlobal(GlobalVariable global, Object? value) {
    value = _typeOperation(global.type, value, cast: true);
    _bindLazy(_globals, global, value, isFinal: global.isFinal);
  }

  Object? _loadLateField(_Instance instance, InstanceField field) {
    if (instance.fields.containsKey(field)) return instance.fields[field];
    final initializer = field.initializer;
    if (initializer == null) return _LateRead().value;
    final value = _typeOperation(
      field.typeFor(instance.type),
      _enter(initializer, [instance]),
      cast: true,
    );
    return _bindLazy(instance.fields, field, value, isFinal: field.isFinal);
  }

  // Commit only after evaluation and conversion, preserving recursive writes
  // both on a final-binding conflict and when the initializer throws.
  Object? _bindLazy<K>(
    Map<K, Object?> storage,
    K slot,
    Object? value, {
    required bool isFinal,
  }) {
    _checkLazyBind(isFinal && storage.containsKey(slot));
    storage[slot] = value;
    return value;
  }

  Object? _loadCell(_Cell cell) {
    if (!identical(cell.value, _uninitialized)) return cell.value;
    if (!cell.type.isLate) {
      fail('Read of an uninitialized definite-assignment local');
    }
    final initializer = cell.initializer;
    if (initializer == null) return _LateRead().value;
    // As with fields and globals, recursive reads and writes remain observable.
    return _storeCell(cell, _call(initializer, const [], const {}));
  }

  Object? _storeCell(_Cell cell, Object? value) {
    if (cell.type.isLate) {
      value = _typeOperation(cell.type.content, value, cast: true);
      _checkLazyBind(
        cell.type.isFinal && !identical(cell.value, _uninitialized),
      );
    }
    cell.value = value;
    return value;
  }

  final _staticFunctions = <Object, _FunctionValue>{};

  final _constants = <Object, Object>{};

  final _types = <ValueType, _TypeValue>{};

  _TypeValue _typeValue(ValueType type) {
    final normalized = type.normalize();
    return _types.putIfAbsent(normalized, () => _TypeValue(normalized));
  }

  // Canonical keys describe IR data, never runtime user equality or hashCode.
  Constant _resolvedConstant(
    Constant value,
    Map<TypeParameterType, ValueType> environment,
  ) {
    if (environment.isEmpty) return value;
    ValueType resolve(ValueType type) => type.substitute(environment);
    Constant child(Constant value) => _resolvedConstant(value, environment);
    return switch (value) {
      ScalarConstant() || TypeConstant() || FunctionConstant() => value,
      RecordConstant(:final type, :final fields) => RecordConstant(
        resolve(type) as RecordType,
        fields.map(child),
      ),
      SequenceConstant(:final type, :final elements) => SequenceConstant(
        resolve(type) as ClassType,
        elements.map(child),
      ),
      MapConstant(:final type, :final entries) => MapConstant(
        resolve(type) as ClassType,
        entries.map((e) => (child(e.$1), child(e.$2))),
      ),
      ObjectConstant(:final type, :final fields) => ObjectConstant(
        resolve(type) as ClassType,
        {for (final e in fields.entries) e.key: child(e.value)},
      ),
    };
  }

  Object? _constant(
    Constant value, [
    Map<TypeParameterType, ValueType> environment = const {},
  ]) {
    value = _resolvedConstant(value, environment);
    return switch (value) {
      ScalarConstant(:final value) => value,
      TypeConstant(:final representedType) => _typeValue(representedType),
      FunctionConstant(
        :final target,
        :final ownerType,
        :final typeArguments,
        :final constructorSignature,
        :final constructorAlias,
        :final constructorTypeArguments,
      ) =>
        _staticFunctions.putIfAbsent(
          value.structuralKey,
          () => _FunctionValue(
            target,
            null,
            const [],
            ownerType?.typeEnvironment ?? const {},
            typeArguments?.toList(),
            null,
            // Proper raw aliases share the target's canonical runtime callable,
            // even when their static bounds spell dynamic instead of Object?.
            constructorAlias == null &&
                    constructorSignature?.typeParameters.isNotEmpty == true
                ? null
                : constructorSignature,
            constructorAlias,
            constructorTypeArguments,
          ),
        ),
      RecordConstant(:final type, :final fields) => _constants.putIfAbsent(
        value.structuralKey,
        () => _RecordValue(
          type as RecordType,
          fields.map((field) => _constant(field)).toList(),
        ),
      ),
      SequenceConstant(:final type, :final elements) => _constants.putIfAbsent(
        value.structuralKey,
        () => _CollectionValue(
          type as ClassType,
          type.declaration == CoreTypes.set
              ? elements.map((element) => _constant(element)).toSet()
              : elements.map((element) => _constant(element)).toList(),
          immutable: true,
        ),
      ),
      MapConstant(:final type, :final entries) => _constants.putIfAbsent(
        value.structuralKey,
        () => _CollectionValue(type as ClassType, {
          for (final e in entries) _constant(e.$1): _constant(e.$2),
        }, immutable: true),
      ),
      ObjectConstant(:final type, :final fields) => _constants.putIfAbsent(
        value.structuralKey,
        () => _Instance(type as ClassType, this)
          ..fields.addAll({
            for (final e in fields.entries) e.key: _constant(e.value),
          }),
      ),
    };
  }

  Object? _enter(
    FunctionTarget target,
    List<Object?> arguments, [
    Map<TypeParameterType, ValueType> environment = const {},
  ]) {
    if (target.kind.hasReceiver) {
      environment = {
        ...environment,
        ...(_runtimeValueType(arguments.first) as ClassType)
            .asInstanceOf(target.owner!)!
            .typeEnvironment,
      };
    }
    if (target.library.toString() == 'dart:async' && !target.kind.hasReceiver) {
      if (target.name == 'scheduleMicrotask' && target.owner == null) {
        scheduleMicrotask(() => _call(arguments.single, const [], const {}));
        return null;
      }
      final owner = target.owner;
      if (owner?.name == 'StreamIterator' && target.name == 'new') {
        return _GuestStreamIterator(
          owner!.substitute(environment) as ClassType,
          StreamIterator(arguments.single as Stream<Object?>),
        );
      }
      if (owner != null &&
          (owner == CoreTypes.future || owner.name == 'Completer')) {
        final type = owner.substitute(environment) as ClassType;
        final element = type.typeArguments.single;
        if (owner.name == 'Completer' &&
            (target.name == 'new' || target.name == 'sync')) {
          return _GuestCompleter(type, target.name == 'sync');
        }
        if (target.name == 'sync') {
          try {
            final value = _call(arguments.single, const [], const {});
            _typeOperation(ValueType.futureOr(element), value, cast: true);
            final actual = _futureType(value);
            if (actual != null && CoreTypes.futureOf(element).accepts(actual)) {
              return value;
            }
            return _GuestFuture(
              CoreTypes.futureOf(element),
              Future<_FutureBox>.sync(() => _FutureBox(value)),
            );
          } catch (error, trace) {
            if (error is _AsyncUnsupported) rethrow;
            return _GuestFuture(
              CoreTypes.futureOf(element),
              Future<_FutureBox>.error(error, trace),
            );
          }
        }
        final Future<_FutureBox> carrier = switch (target.name) {
          'value' => Future<_FutureBox>.value(
            _boxOrAdopt(arguments.firstOrNull, element),
          ),
          'error' => Future<_FutureBox>.error(
            arguments.first!,
            _asyncTrace(arguments.elementAtOrNull(1)),
          ),
          'microtask' => Future<_FutureBox>.microtask(
            () => _boxOrAdopt(
              _call(arguments.single, const [], const {}),
              element,
            ),
          ),
          _ => throw _AsyncUnsupported(
            'Unmodeled async factory ${target.name}',
          ),
        };
        return _GuestFuture(CoreTypes.futureOf(element), carrier);
      }
    }
    if (target.owner == ValueType.object &&
        target.kind == .getter &&
        target.name == 'runtimeType') {
      return _typeValue(_runtimeValueType(arguments.single));
    }
    // Keep access on the same canonical storage used by MakeInvocation.
    if (_isInvocationFactory(target) &&
        program.implementationOf(target) is! IrFunction) {
      return target.name == 'method'
          ? _invocation(arguments[0], null, arguments[1], arguments[2], 0)
          : _invocation(
              arguments[0],
              arguments[1],
              arguments[2],
              arguments[3],
              0,
            );
    }
    if (target.owner == CoreTypes.invocation &&
        target.kind == .initializer &&
        target.name == 'new') {
      return null;
    }
    if (_isInvocationGetter(target)) {
      final instance = arguments.single as _Instance;
      if (target.owner == CoreTypes.invocationStorage &&
          instance.type == CoreTypes.invocationStorage) {
        return switch (target.name) {
          'memberName' => instance.fields[CoreTypes.invocationMemberName],
          'typeArguments' => instance.fields[CoreTypes.invocationTypeArguments],
          'positionalArguments' =>
            instance.fields[CoreTypes.invocationPositionalArguments],
          'namedArguments' =>
            instance.fields[CoreTypes.invocationNamedArguments],
          'isMethod' => instance.fields[CoreTypes.invocationKind] == 0,
          'isGetter' => instance.fields[CoreTypes.invocationKind] == 1,
          'isSetter' => instance.fields[CoreTypes.invocationKind] == 2,
          'isAccessor' => instance.fields[CoreTypes.invocationKind] != 0,
          _ => throw StateError('Invalid Invocation getter'),
        };
      }
      if (target.owner == CoreTypes.invocation) {
        if (target.name == 'typeArguments') return _emptyList(.typeType);
        if (target.name == 'isAccessor') {
          bool flag(String name) => _invoke(
            _FunctionValue(
              _resolveMember(instance, _invocationFlags[name]!),
              instance,
            ),
            const [],
            const {},
          ) as bool;
          return flag('isGetter') || flag('isSetter');
        }
      }
    }
    if (program.implementationOf(target) case final IrFunction body) {
      return run(body, arguments, environment);
    }
    if (target.owner == ValueType.string) {
      final receiver = arguments.first as String;
      if (target.name == '+') return receiver + (arguments[1] as String);
      if (target.name == '*') return receiver * (arguments[1] as int);
    }
    if (target.library.toString() == 'dart:core' &&
        target.name == 'identical') {
      return identical(arguments[0], arguments[1]);
    }
    if (target.library == ValueType.noSuchMethodError.library &&
        target.owner == ValueType.noSuchMethodError &&
        target.kind == .factory &&
        target.name == 'withInvocation') {
      return _noSuchMethodError(arguments[0], arguments[1]!);
    }
    if (_isObjectNoSuchMethod(target)) {
      throw _noSuchMethodError(arguments[0], arguments[1]!);
    }
    if (_isObjectToString(target)) {
      return (arguments.single as _Instance).defaultString;
    }
    if (target == _symbolToString) return arguments.first.toString();
    if (arguments.firstOrNull case final _Instance instance
        when _isSymbolMember(target) &&
            CoreTypes.symbol.accepts(instance.type)) {
      return target.kind == .getter
          ? instance.hashCode
          : "Instance of '${instance.type.dartName}'";
    }
    if (target.library.toString() == 'dart:async') {
      throw _AsyncUnsupported('Unmodeled async entry ${target.name}');
    }
    return imports[(target.library, target.name)]!(arguments.single as int);
  }

  _Instance _construct(
    FunctionTarget init,
    List<Object?> arguments, [
    ClassType? instantiatedType,
  ]) {
    if (init.owner == CoreTypes.invocationStorage &&
        init.kind == .initializer &&
        (init.name == 'getter' ||
            init.name == 'setter' ||
            init.name == 'method')) {
      if (init.name == 'method') {
        return _invocation(
          arguments[0],
          arguments[1],
          arguments[2],
          arguments[3],
          0,
        );
      }
      return _invocation(
        arguments[0],
        null,
        init.name == 'setter' ? arguments[1] : null,
        null,
        init.name == 'getter' ? 1 : 2,
      );
    }
    final instance = _Instance(instantiatedType ?? init.owner!, this);
    if (init.owner == CoreTypes.mapEntry) {
      instance.fields[CoreTypes.mapEntryKey] = arguments[0];
      instance.fields[CoreTypes.mapEntryValue] = arguments[1];
    } else if (init.owner == CoreTypes.symbolStorage) {
      instance.fields[CoreTypes.symbolName] = arguments.single;
      instance.fields[CoreTypes.symbolPrivateLibrary] = null;
    } else if (init.owner != ValueType.object) {
      _enter(init, [instance, ...arguments]);
    }
    return instance;
  }

  Object? _emptyList(ValueType element) =>
      _constant(SequenceConstant(CoreTypes.listOf(element), const []));

  Object? _emptyNamed(ValueType value) => _constant(
    MapConstant(CoreTypes.mapOf(CoreTypes.symbol, value), const []),
  );

  _CollectionValue _invocationList(Object source, ValueType element) {
    if (source is _Instance &&
        (source.type.asInstanceOf(CoreTypes.list) != null ||
            source.type.asInstanceOf(CoreTypes.set) != null)) {
      // The SDK's List/Set protocols have efficient length. A zero length
      // skips iterator acquisition; mismatched lengths fail during/after copy.
      final length = _member(source, 'length', .getter, []) as int;
      final storage = List<Object?>.filled(length, null);
      if (length > 0) {
        var index = 0;
        final iterator = _iterator(source);
        while (_moveNext(iterator)) {
          final value = _typeOperation(element, _current(iterator), cast: true);
          storage[index++] = value;
        }
        if (index != length) throw ConcurrentModificationError(source);
      }
      return _CollectionValue(
        CoreTypes.listOf(element),
        storage,
        immutable: true,
      );
    }
    final list = _CollectionValue(CoreTypes.listOf(element), <Object?>[]);
    _spread(list, source, false, false, false);
    return _CollectionValue(list.type, list.storage, immutable: true);
  }

  _Instance _invocation(
    Object? memberName,
    Object? types,
    Object? positional,
    Object? named,
    int kind,
  ) {
    // Evaluate and copy in SDK order; later protocols are never entered after
    // an earlier traversal or element conversion fails.
    final typeArguments = types == null
        ? _emptyList(.typeType)
        : _invocationList(types, .typeType);
    final positionalArguments = kind == 1
        ? _emptyList(.object)
        : kind == 2
        ? _CollectionValue(
            CoreTypes.listOf(ValueType.object.nullable),
            <Object?>[positional],
            immutable: true,
          )
        : positional == null
        ? _emptyList(ValueType.object.nullable)
        : _invocationList(positional, ValueType.object.nullable);
    Object? namedArguments;
    if (kind != 0) {
      namedArguments = _emptyNamed(.object);
    } else {
      final empty =
          named == null ||
          (named is _Instance
              ? _member(named, 'isEmpty', .getter, []) as bool
              : ((named is _CollectionValue ? named.storage : named)
                        as Map<Object?, Object?>)
                    .isEmpty);
      if (empty) {
        namedArguments = _emptyNamed(ValueType.object.nullable);
      } else {
        final map = _CollectionValue(
          CoreTypes.mapOf(CoreTypes.symbol, ValueType.object.nullable),
          <Object?, Object?>{},
        );
        _spread(map, named, true, false, false);
        namedArguments = _CollectionValue(
          map.type,
          map.storage,
          immutable: true,
        );
      }
    }
    return _Instance(CoreTypes.invocationStorage, this)
      ..fields.addAll({
        CoreTypes.invocationMemberName: memberName,
        CoreTypes.invocationTypeArguments: typeArguments,
        CoreTypes.invocationPositionalArguments: positionalArguments,
        CoreTypes.invocationNamedArguments: namedArguments,
        CoreTypes.invocationKind: kind,
      });
  }

  bool _isInvocationFactory(FunctionTarget target) =>
      target.owner == CoreTypes.invocation &&
      target.kind == .factory &&
      (target.name == 'method' || target.name == 'genericMethod');

  Object? _defaultArgument(
    FunctionTarget target,
    int index,
    Map<TypeParameterType, ValueType> environment,
  ) {
    final defaults = program.implementationOf(target)?.defaults;
    if (defaults != null && defaults.containsKey(index)) {
      return _constant(defaults[index]!, environment);
    }
    if (_isInvocationFactory(target) &&
        index == (target.name == 'method' ? 2 : 3)) {
      return null;
    }
    throw StateError('Missing fixture default: ${target.name}[$index]');
  }

  Object? _invoke(
    _FunctionValue fn,
    List<Object?> positional,
    Map<String, Object?> named, [
    List<ValueType> typeArguments = const [],
  ]) {
    var target = fn.target;
    var environment = {
      ...fn.environment,
      if (fn.receiver != null)
        ...(_runtimeValueType(fn.receiver) as ClassType)
            .asInstanceOf(target.owner!)!
            .typeEnvironment,
    };
    final argumentsForTypes = fn.typeArguments ?? typeArguments;
    final binders = fn.genericSignature.typeParameters;
    final genericSignature =
        fn.genericSignature.substitute(environment) as FunctionType;
    final appliedSignature = _instantiateSignature(
      genericSignature,
      argumentsForTypes,
    );
    environment = {
      ...environment,
      for (final (i, parameter) in binders.indexed)
        parameter: argumentsForTypes[i],
    };
    final targetArguments =
        fn.constructorTypeArguments
            ?.map((t) => t.substitute(environment))
            .toList() ??
        argumentsForTypes;
    if (fn.constructorTypeArguments != null) {
      environment.addAll({
        for (final (i, p) in target.typeParameters.indexed)
          p: targetArguments[i],
      });
    }
    if (target.kind == .initializer || target.kind == .factory) {
      final resolved = target.resolveConstruction(
        appliedSignature.result as ClassType,
      );
      target = resolved.target;
      environment = {...environment, ...resolved.ownerType.typeEnvironment};
    }
    final declaredSignature =
        target.signature.substitute(environment) as FunctionType;
    final signature = declaredSignature.typeParameters.isEmpty
        ? declaredSignature
        : _instantiateSignature(declaredSignature, targetArguments);
    final arguments = signature.bind<Object?>(
      positional,
      named,
      (i) => _defaultArgument(target, i, environment),
    );
    for (final (i, arg) in arguments.indexed) {
      _typeOperation(signature.parameters[i], arg, cast: true);
    }
    return target.kind == .initializer
        ? _construct(
            target,
            arguments,
            (target.owner!).substitute(environment) as ClassType,
          )
        : _enter(target, [
            if (target.kind == .closure) fn.genericOrigin ?? fn,
            ...fn.captures,
            ?fn.receiver,
            ...arguments,
          ], environment);
  }

  bool _matchesShape(
    FunctionType signature,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types,
  ) =>
      positional.length >= signature.requiredPositional &&
      positional.length <= signature.positionalCount &&
      named.keys.every(signature.named.containsKey) &&
      signature.named.entries.every(
        (e) => !e.value.required || named.containsKey(e.key),
      ) &&
      (types.isEmpty || types.length == signature.typeParameters.length);

  Object? _dynamicFunction(
    _FunctionValue function,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types,
    Object? failureReceiver,
    MemberSelector selector,
  ) {
    final signature = function.reifiedSignature;
    if (!_matchesShape(signature, positional, named, types)) {
      return _missingDynamic(
        failureReceiver,
        selector,
        positional,
        named,
        types,
      );
    }
    final arguments =
        function.typeArguments ??
        (types.isNotEmpty ? types : signature.defaultTypeArguments);
    return _invoke(function, positional, named, arguments);
  }

  static MemberSelector _selector(String name, [FunctionKind kind = .method]) =>
      (kind: kind, name: name, privateScope: null);

  _Instance _invocationSymbol(String name, [Uri? library]) =>
      _Instance(CoreTypes.symbolStorage, this)
        ..fields[CoreTypes.symbolName] = name
        ..fields[CoreTypes.symbolPrivateLibrary] = library?.toString();

  _Instance _runtimeInvocation(
    MemberSelector selector,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types, {
    bool typedForwarder = false,
  }) {
    Object? symbol(String name, [Uri? library]) => typedForwarder
        ? _constant(
            ObjectConstant(CoreTypes.symbolStorage, {
              CoreTypes.symbolName: Constant.string(name),
              CoreTypes.symbolPrivateLibrary: library == null
                  ? const Constant.nullValue()
                  : Constant.string(library.toString()),
            }),
          )
        : _invocationSymbol(name, library);
    final name = selector.kind == .setter ? '${selector.name}=' : selector.name;
    final elementType = typedForwarder
        ? ValueType.dynamicType
        : ValueType.object.nullable;
    // Generated forwarders canonicalize symbols and empty dynamic lists, but
    // always allocate their named-argument view. Raw missing dispatch instead
    // shares Object? empty constants; public accessor factories use Object.
    return _Instance(CoreTypes.invocationStorage, this)
      ..fields.addAll({
        CoreTypes.invocationMemberName: symbol(
          name,
          selector.privateScope as Uri?,
        ),
        CoreTypes.invocationTypeArguments: types.isEmpty
            ? _emptyList(.typeType)
            : _CollectionValue(
                CoreTypes.listOf(ValueType.typeType),
                types.map(_typeValue).toList(),
                immutable: true,
              ),
        CoreTypes.invocationPositionalArguments: positional.isEmpty
            ? _emptyList(elementType)
            : _CollectionValue(
                CoreTypes.listOf(elementType),
                positional.toList(),
                immutable: true,
              ),
        CoreTypes.invocationNamedArguments: named.isEmpty && !typedForwarder
            ? _emptyNamed(elementType)
            : _CollectionValue(CoreTypes.mapOf(CoreTypes.symbol, elementType), {
                for (final entry in named.entries)
                  symbol(entry.key): entry.value,
              }, immutable: true),
        CoreTypes.invocationKind: selector.kind == .method
            ? 0
            : selector.kind == .getter
            ? 1
            : 2,
      });
  }

  Object? _missingDynamic(
    Object? receiver,
    MemberSelector selector,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types,
  ) {
    final name = selector.kind == .setter ? '${selector.name}=' : selector.name;
    if (receiver is _Instance) {
      final lookup = program.lookupMember(
        receiver.type,
        _selector('noSuchMethod'),
      );
      if (lookup.target case final target?) {
        final names = named.keys.toList()..sort();
        final invocation = _runtimeInvocation(selector, positional, {
          for (final name in names) name: named[name],
        }, types);
        return _invoke(_FunctionValue(target, receiver), [
          invocation,
        ], const {});
      }
      if (lookup.unsupportedForwarder ||
          lookup.unmodeledBoundary != null &&
              receiver.type != CoreTypes.symbolStorage &&
              receiver.type != CoreTypes.invocationStorage &&
              receiver.type != CoreTypes.mapEntry) {
        throw UnsupportedError('Unmodeled fixture noSuchMethod implementation');
      }
    }
    // The native adapter supplies real error classification. Diagnostic text
    // cannot encode represented generic Type values or private-symbol identity.
    final invocation = selector.kind == .getter
        ? Invocation.getter(Symbol(name))
        : selector.kind == .setter
        ? Invocation.setter(Symbol(name), positional.single)
        : Invocation.method(Symbol(name), positional, {
            for (final e in named.entries) Symbol(e.key): e.value,
          });
    throw NoSuchMethodError.withInvocation(receiver, invocation);
  }

  Object? _dynamicDispatch(
    Object? receiver,
    MemberSelector selector,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types,
  ) {
    if (receiver is _FunctionValue && selector.name == 'call') {
      if (selector.kind == .getter) return receiver;
      if (selector.kind == .method) {
        return _dynamicFunction(
          receiver,
          positional,
          named,
          types,
          receiver,
          selector,
        );
      }
    }
    if (receiver is _NativeFunction && selector == _selector('call', .getter)) {
      return receiver;
    }
    if (receiver is _NativeFunction && selector == _selector('call')) {
      if (!_matchesShape(receiver.signature, positional, named, types)) {
        return _missingDynamic(receiver, selector, positional, named, types);
      }
      if (named.isNotEmpty ||
          types.isNotEmpty ||
          receiver.signature.typeParameters.isNotEmpty ||
          positional.length != receiver.signature.parameters.length) {
        throw UnsupportedError('Unmodeled native callback argument binding');
      }
      for (final (i, value) in positional.indexed) {
        _typeOperation(receiver.signature.parameters[i], value, cast: true);
      }
      return receiver.callback(positional);
    }
    if (receiver is _Instance) {
      final lookup = program.lookupMember(receiver.type, selector);
      if (lookup.target case final target?) {
        return _dynamicFunction(
          _FunctionValue(target, receiver),
          positional,
          named,
          types,
          receiver,
          selector,
        );
      }
      if (lookup.unsupportedForwarder) {
        throw UnsupportedError(
          'Unsupported typed noSuchMethod forwarder: ${selector.name}',
        );
      }
      if (selector.kind == .method || selector.kind == .getter) {
        final alternate = (
          kind: selector.kind == .method
              ? FunctionKind.getter
              : FunctionKind.method,
          name: selector.name,
          privateScope: selector.privateScope,
        );
        final other = program.lookupMember(receiver.type, alternate);
        if (other.target case final target?) {
          final function = _FunctionValue(target, receiver);
          if (selector.kind == .getter) return function;
          final value = _invoke(function, const [], const {});
          return _dynamicDispatch(
            value,
            _selector('call'),
            positional,
            named,
            types,
          );
        }
        if (other.unsupportedForwarder) {
          throw UnsupportedError(
            'Unsupported typed noSuchMethod forwarder: ${selector.name}',
          );
        }
      }
      // Invocation's deliberately modeled SDK storage and default getters.
      if ((selector.kind == .getter || selector.kind == .method) &&
          selector.privateScope == null) {
        final target = FunctionTarget(
          CoreTypes.invocation.library,
          selector.name,
          .dynamicType,
          const [],
          owner: CoreTypes.invocation,
          kind: .getter,
        );
        if (_isInvocationGetter(target) &&
            receiver.type.asInstanceOf(CoreTypes.invocation) != null) {
          final value = _invoke(
            _FunctionValue(_resolveMember(receiver, target), receiver),
            const [],
            const {},
          );
          return selector.kind == .getter
              ? value
              : _dynamicDispatch(
                  value,
                  _selector('call'),
                  positional,
                  named,
                  types,
                );
        }
      }
      if (lookup.unmodeledBoundary != null &&
          receiver.type != CoreTypes.symbolStorage &&
          receiver.type != CoreTypes.invocationStorage &&
          receiver.type != CoreTypes.mapEntry) {
        throw UnsupportedError(
          'Unmodeled fixture dynamic boundary: ${lookup.unmodeledBoundary!.dartName}.${selector.name}',
        );
      }
    }
    if (selector.kind == .method &&
        selector.privateScope == null &&
        (const {'hashCode', 'runtimeType'}.contains(selector.name) ||
            (receiver is _CollectionValue || receiver is String) &&
                const {
                  'length',
                  'isEmpty',
                  'isNotEmpty',
                }.contains(selector.name) ||
            receiver is _RecordValue &&
                receiver.type.slots.containsKey(selector.name) ||
            receiver is _Instance &&
                receiver.type == CoreTypes.mapEntry &&
                const {'key', 'value'}.contains(selector.name))) {
      final value = _dynamicBridge(
        receiver,
        _selector(selector.name, .getter),
        const [],
        const {},
        const [],
      );
      return _dynamicDispatch(
        value,
        _selector('call'),
        positional,
        named,
        types,
      );
    }
    final bridge = _dynamicBridge(receiver, selector, positional, named, types);
    if (!identical(bridge, _noDynamicBridge)) return bridge;
    if (receiver == null ||
        receiver is _Instance ||
        receiver is _FunctionValue ||
        receiver is _NativeFunction ||
        selector.name == 'call' &&
            (receiver is num ||
                receiver is bool ||
                receiver is String ||
                receiver is _TypeValue ||
                receiver is _CollectionValue ||
                receiver is _RecordValue)) {
      return _missingDynamic(receiver, selector, positional, named, types);
    }
    throw UnsupportedError(
      'Unmodeled fixture dynamic member: ${selector.name}',
    );
  }

  Object? _dynamicBridge(
    Object? receiver,
    MemberSelector selector,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types,
  ) {
    if (receiver is _GuestFuture ||
        receiver is _GuestCompleter ||
        receiver is _GuestStreamIterator) {
      if (selector.name == 'runtimeType' && selector.kind == .getter) {
        return _typeValue(_runtimeValueType(receiver));
      }
      return _asyncMember(receiver!, selector, positional, named, types);
    }

    if (selector.privateScope != null) return _noDynamicBridge;
    final name = selector.name;
    Object? invoke(int count, Object? Function() body) {
      if (positional.length != count || named.isNotEmpty || types.isNotEmpty) {
        return _missingDynamic(receiver, selector, positional, named, types);
      }
      return body();
    }

    if (name == 'toString' &&
        receiver is _Instance &&
        receiver.type.library?.scheme == 'dart' &&
        receiver.type != CoreTypes.symbolStorage) {
      throw UnsupportedError('Unmodeled SDK toString receiver');
    }
    if (selector.kind == .getter) {
      if (name == 'runtimeType') return _typeValue(_runtimeValueType(receiver));
      if (name == 'hashCode') return receiver.hashCode;
      if (name == 'toString' && receiver is _Instance) {
        return _FunctionValue(
          _resolveMember(receiver, _Instance._string),
          receiver,
        );
      }
      if (receiver is _GeneratorIterable && name == 'iterator') {
        return receiver.iterator;
      }
      if (receiver is _GeneratorIterator) {
        if (name == 'current') return receiver.current;
        if (name == 'moveNext') {
          return _NativeFunction(
            FunctionType(.boolean, const []),
            (_) => receiver.moveNext(),
            (receiver, _selector('moveNext')),
          );
        }
      }
      if (const {'toString', '==', 'noSuchMethod'}.contains(name)) {
        final method = _selector(name);
        final signature = FunctionType(
          name == 'toString'
              ? .string
              : name == '=='
              ? .boolean
              : .dynamicType,
          name == 'toString'
              ? []
              : [
                  name == 'noSuchMethod'
                      ? CoreTypes.invocation
                      : ValueType.object.nullable,
                ],
        );
        return _NativeFunction(
          signature,
          (args) => _dynamicBridge(receiver, method, args, const {}, const []),
          (receiver, method),
        );
      }
      if (receiver is _RecordValue) {
        final slot = receiver.type.slots[name];
        if (slot != null) return receiver.fields[slot];
      }
      if (receiver is _Instance && receiver.type == CoreTypes.mapEntry) {
        if (name == 'key') return receiver.fields[CoreTypes.mapEntryKey];
        if (name == 'value') return receiver.fields[CoreTypes.mapEntryValue];
      }
      if (receiver is _CollectionValue) {
        final dynamic storage = receiver.storage;
        if (name == 'length') return storage.length;
        if (name == 'isEmpty') return storage.isEmpty;
        if (name == 'isNotEmpty') return storage.isNotEmpty;
      }
      if (receiver is String) {
        if (name == 'length') return receiver.length;
        if (name == 'isEmpty') return receiver.isEmpty;
        if (name == 'isNotEmpty') return receiver.isNotEmpty;
      }
      return _noDynamicBridge;
    }
    if (selector.kind != .method) return _noDynamicBridge;
    if (receiver is _GeneratorIterator && name == 'moveNext') {
      return invoke(0, receiver.moveNext);
    }
    if (name == 'toString') {
      return invoke(0, () {
        // Aggregate/function/error formatting needs its own representation
        // model; never leak host wrapper names through an Object-typed call.
        if (receiver != null &&
            receiver is! _Instance &&
            receiver is! _TypeValue &&
            receiver is! num &&
            receiver is! bool &&
            receiver is! String) {
          throw UnsupportedError('Unmodeled fixture toString receiver');
        }
        return receiver.toString();
      });
    }
    if (name == '==') return invoke(1, () => receiver == positional.single);
    if (name == 'noSuchMethod') {
      return invoke(1, () {
        final invocation = positional.single;
        _typeOperation(CoreTypes.invocation, invocation, cast: true);
        throw _noSuchMethodError(receiver, invocation!);
      });
    }
    if (receiver is num) {
      if (name == 'unary-') return invoke(0, () => -receiver);
      if (receiver is int && name == '~') return invoke(0, () => ~receiver);
      if (const {
        '+',
        '-',
        '*',
        '/',
        '~/',
        '%',
        '<',
        '<=',
        '>',
        '>=',
      }.contains(name)) {
        return invoke(1, () {
          final b = positional.single as num;
          return switch (name) {
            '+' => receiver + b,
            '-' => receiver - b,
            '*' => receiver * b,
            '/' => receiver / b,
            '~/' => receiver ~/ b,
            '%' => receiver % b,
            '<' => receiver < b,
            '<=' => receiver <= b,
            '>' => receiver > b,
            _ => receiver >= b,
          };
        });
      }
      if (receiver is int &&
          const {'&', '|', '^', '<<', '>>', '>>>'}.contains(name)) {
        return invoke(1, () {
          final b = positional.single as int;
          return switch (name) {
            '&' => receiver & b,
            '|' => receiver | b,
            '^' => receiver ^ b,
            '<<' => receiver << b,
            '>>' => receiver >> b,
            _ => receiver >>> b,
          };
        });
      }
    }
    if (receiver is String) {
      if (name == '+') {
        return invoke(1, () => receiver + (positional.single as String));
      }
      if (name == '[]') {
        return invoke(1, () => receiver[positional.single as int]);
      }
    }
    if (receiver is _CollectionValue) {
      final storage = receiver.storage;
      if (name == '[]' && (storage is List || storage is Map)) {
        return invoke(
          1,
          () => storage is List
              ? storage[positional.single as int]
              : (storage as Map)[positional.single],
        );
      }
      if (name == 'containsKey' && storage is Map) {
        return invoke(1, () => storage.containsKey(positional.single));
      }
      if (name == 'add' && (storage is List || storage is Set)) {
        return invoke(1, () {
          _typeOperation(
            receiver.type.typeArguments.single,
            positional.single,
            cast: true,
          );
          receiver.checkMutable();
          return _add(receiver, positional.single);
        });
      }
      if (name == '[]=' && (storage is List || storage is Map)) {
        return invoke(2, () {
          final arguments = receiver.type.typeArguments;
          if (storage is Map) {
            _typeOperation(arguments[0], positional[0], cast: true);
            _typeOperation(arguments[1], positional[1], cast: true);
            receiver.checkMutable();
            storage[positional[0]] = positional[1];
          } else {
            final index = positional[0] as int;
            _typeOperation(arguments.single, positional[1], cast: true);
            receiver.checkMutable();
            (storage as List)[index] = positional[1];
          }
          return null;
        });
      }
    }
    return _noDynamicBridge;
  }

  StackTrace? _asyncTrace(Object? value) {
    _typeOperation(ValueType.stackTrace.nullable, value, cast: true);
    if (value == null || value is StackTrace) return value as StackTrace?;
    throw _AsyncUnsupported('Guest StackTrace async adapter');
  }

  int? _asyncErrorArity(Object? callback) {
    _typeOperation(.function, callback, cast: true);
    final signature = switch (callback) {
      _FunctionValue() => callback.reifiedSignature,
      _NativeFunction(:final signature) => signature,
      _ => throw _AsyncUnsupported('Async error callback shape'),
    };
    for (final parameters in <List<ValueType>>[
      [.object, .stackTrace],
      [.object],
    ]) {
      if (FunctionType(.dynamicType, parameters).accepts(signature)) {
        return parameters.length;
      }
    }
    return null;
  }

  FutureOr<_FutureBox> _asyncErrorCallback(
    Object? callback,
    Object error,
    StackTrace trace,
    ValueType result,
  ) {
    if (error is _AsyncUnsupported) Error.throwWithStackTrace(error, trace);
    final arity = _asyncErrorArity(callback);
    if (arity == null) throw TypeError();
    final value = _call(
      callback,
      arity == 2 ? [error, trace] : [error],
      const {},
    );
    try {
      return _boxOrAdopt(value, result);
    } on TypeError {
      throw ArgumentError('Error handler must return the future value type');
    }
  }

  Object? _asyncMember(
    Object receiver,
    MemberSelector selector,
    List<Object?> positional,
    Map<String, Object?> named,
    List<ValueType> types,
  ) {
    if (selector.privateScope != null) {
      throw _AsyncUnsupported('Private async member');
    }
    if (receiver is _GuestStreamIterator) {
      if (positional.isNotEmpty || named.isNotEmpty || types.isNotEmpty) {
        throw _AsyncUnsupported('StreamIterator invocation shape');
      }
      return switch ((selector.kind, selector.name)) {
        (.getter, 'current') => receiver.iterator.current,
        (.method, 'moveNext') => _GuestFuture(
          CoreTypes.futureOf(.boolean),
          receiver.iterator.moveNext().then(_FutureBox.new),
        ),
        (.method, 'cancel') => _GuestFuture(
          CoreTypes.futureOf(.dynamicType),
          receiver.iterator.cancel().then(_FutureBox.new),
        ),
        _ => throw _AsyncUnsupported(
          'Unmodeled StreamIterator member ${selector.name}',
        ),
      };
    }
    if (receiver is _GuestCompleter) {
      if (selector.kind == .getter) {
        return switch (selector.name) {
          'future' => receiver.future,
          'isCompleted' => receiver.completer.isCompleted,
          _ => throw _AsyncUnsupported(
            'Completer member extraction ${selector.name}',
          ),
        };
      }
      if (selector.kind != .method || named.isNotEmpty || types.isNotEmpty) {
        throw _AsyncUnsupported('Completer invocation shape');
      }
      switch (selector.name) {
        case 'complete' when positional.length <= 1:
          _typeOperation(
            ValueType.futureOr(receiver.type.typeArguments.single).nullable,
            positional.firstOrNull,
            cast: true,
          );
          if (receiver.completer.isCompleted) {
            throw StateError('Future already completed');
          }
          receiver.completer.complete(
            _boxOrAdopt(
              positional.firstOrNull,
              receiver.type.typeArguments.single,
            ),
          );
          return null;
        case 'completeError'
            when positional.length == 1 || positional.length == 2:
          _typeOperation(.object, positional.first, cast: true);
          receiver.completer.completeError(
            positional.first!,
            _asyncTrace(positional.elementAtOrNull(1)),
          );
          return null;
        default:
          throw _AsyncUnsupported(
            'Unmodeled Completer member ${selector.name}',
          );
      }
    }
    final future = receiver as _GuestFuture;
    if (selector.kind != .method) {
      throw _AsyncUnsupported('Future member extraction ${selector.name}');
    }
    final element = future.type.typeArguments.single;
    if (selector.name == 'then' &&
        positional.length == 1 &&
        named.keys.every((name) => name == 'onError') &&
        types.length <= 1) {
      final result = types.firstOrNull ?? ValueType.dynamicType;
      final onError = named['onError'];
      _typeOperation(
        FunctionType(ValueType.futureOr(result), [element]),
        positional.single,
        cast: true,
      );
      if (onError != null && _asyncErrorArity(onError) == null) {
        throw ArgumentError('Invalid async error handler');
      }
      return _GuestFuture(
        CoreTypes.futureOf(result),
        future.carrier.then<_FutureBox>(
          (box) => _boxOrAdopt(
            _call(positional.single, [box.value], const {}),
            result,
          ),
          onError: onError == null
              ? null
              : (Object error, StackTrace trace) =>
                    _asyncErrorCallback(onError, error, trace, result),
        ),
      );
    }
    if (selector.name == 'catchError' &&
        positional.length == 1 &&
        named.keys.every((name) => name == 'test') &&
        types.isEmpty) {
      final predicate = named['test'];
      if (Zone.current != Zone.root &&
          _asyncErrorArity(positional.single) == null) {
        throw ArgumentError('Invalid async error handler');
      }
      if (predicate != null) {
        _typeOperation(
          FunctionType(.boolean, [.object]),
          predicate,
          cast: true,
        );
      }
      return _GuestFuture(
        future.type,
        future.carrier.catchError(
          (Object error, StackTrace trace) =>
              _asyncErrorCallback(positional.single, error, trace, element),
          test: predicate == null
              ? null
              : (Object error) =>
                    error is! _AsyncUnsupported &&
                    _call(predicate, [error], const {}) as bool,
        ),
      );
    }
    throw _AsyncUnsupported('Unmodeled Future member ${selector.name}');
  }

  Object? _call(
    Object? function,
    List<Object?> positional,
    Map<String, Object?> named, [
    List<ValueType> typeArguments = const [],
  ]) => switch (function) {
    _FunctionValue() => _invoke(function, positional, named, typeArguments),
    _NativeFunction(:final callback) => callback(positional),
    _ => throw StateError('Not a fixture function: $function'),
  };

  Object? _member(
    _Instance instance,
    String name,
    FunctionKind kind,
    List<Object?> arguments,
  ) {
    final target = program
        .lookupMember(instance.type, _selector(name, kind))
        .target!;
    return _invoke(_FunctionValue(target, instance), arguments, const {});
  }

  // These SDK declarations have no bodies in the fixture program. Match their
  // nominal owners as well as selectors, and always prefer user dispatch.
  static final _symbolToString = FunctionTarget(
    CoreTypes.symbolStorage.library,
    'toString',
    .string,
    [],
    owner: CoreTypes.symbolStorage,
    kind: .method,
  );

  bool _isSymbolMember(FunctionTarget member) =>
      member.owner == CoreTypes.symbol &&
          member.kind == .getter &&
          member.name == 'hashCode' ||
      member.owner == ValueType.object &&
          member.kind == .method &&
          member.name == 'toString';

  bool _isInvocationGetter(FunctionTarget member) =>
      (member.owner == CoreTypes.invocation ||
          member.owner == CoreTypes.invocationStorage) &&
      member.kind == .getter &&
      const {
        'memberName',
        'typeArguments',
        'positionalArguments',
        'namedArguments',
        'isMethod',
        'isGetter',
        'isSetter',
        'isAccessor',
      }.contains(member.name);

  static final _invocationFlags = {
    for (final name in ['isGetter', 'isSetter'])
      name: FunctionTarget(
        CoreTypes.invocation.library,
        name,
        .boolean,
        const [],
        owner: CoreTypes.invocation,
        kind: .getter,
        isAbstract: true,
      ),
  };

  static final _invocationDefaults = {
    for (final entry in {
      'typeArguments': CoreTypes.listOf(ValueType.typeType),
      'isAccessor': ValueType.boolean,
    }.entries)
      entry.key: FunctionTarget(
        CoreTypes.invocation.library,
        entry.key,
        entry.value,
        const [],
        owner: CoreTypes.invocation,
        kind: .getter,
      ),
  };

  final _invocationStorageGetters = <String, FunctionTarget>{};

  NoSuchMethodError _noSuchMethodError(Object? receiver, Object invocation) =>
      NoSuchMethodError.withInvocation(
        receiver,
        _GuestInvocation(this, invocation),
      );

  static bool _isObjectToString(FunctionTarget target) =>
      target.owner == ValueType.object &&
      target.kind == .method &&
      target.name == 'toString';

  static bool _isObjectNoSuchMethod(FunctionTarget target) =>
      target.library == ValueType.object.library &&
      target.owner == ValueType.object &&
      target.kind == .method &&
      target.name == 'noSuchMethod';

  FunctionTarget _resolveMember(_Instance instance, FunctionTarget member) {
    final target = program.dispatch(instance.type, member);
    if (target != null) return target;
    if (_isInvocationGetter(member) &&
        instance.type == CoreTypes.invocationStorage) {
      return _invocationStorageGetters.putIfAbsent(
        member.name,
        () => FunctionTarget(
          CoreTypes.invocationStorage.library,
          member.name,
          member.returnType,
          const [],
          owner: CoreTypes.invocationStorage,
          kind: .getter,
        ),
      );
    }
    if (member.kind == .getter) {
      // An abstract redeclaration or unrelated interface can supply the static
      // selector while the receiver still inherits Invocation's concrete body.
      final inherited = _invocationDefaults[member.name];
      if (inherited != null) {
        for (
          ClassType? type = instance.type;
          type != null;
          type = type.superclass
        ) {
          if (type == CoreTypes.invocation) return inherited;
        }
      }
    }
    if (_isSymbolMember(member) && CoreTypes.symbol.accepts(instance.type)) {
      // Keep the implementation identity: a direct Object.toString call must
      // not execute the Symbol implementation or redispatch a user override.
      return member.owner == ValueType.object &&
              instance.type == CoreTypes.symbolStorage
          ? _symbolToString
          : _isObjectToString(member)
          ? _Instance._string
          : member;
    }
    final lookup = program.lookupMember(instance.type, member.selector);
    if (lookup.unsupportedForwarder) {
      throw UnsupportedError('Unmodeled fixture noSuchMethod forwarder');
    }
    // Only proven absence through Object permits the SDK implementation. An
    // unknown imported superclass may supply its own implementation.
    if ((_isObjectNoSuchMethod(member) || _isObjectToString(member)) &&
        lookup.target == null &&
        lookup.unmodeledBoundary == null) {
      return _isObjectToString(member) ? _Instance._string : member;
    }
    if (_isObjectToString(member) && lookup.unmodeledBoundary != null) {
      throw UnsupportedError('Unmodeled SDK toString implementation');
    }
    throw StateError('Missing fixture member: ${member.name}');
  }

  Object _iterator(Object? value) => switch (value) {
    _Instance() => _member(value, 'iterator', .getter, [])!,
    _CollectionValue(:final storage) => (storage as Iterable<Object?>).iterator,
    Iterable<Object?>() => value.iterator,
    _ => throw TypeError(),
  };

  bool _moveNext(Object iterator) => iterator is _Instance
      ? _member(iterator, 'moveNext', .method, []) as bool
      : (iterator as Iterator<Object?>).moveNext();

  String _fromCharCodes(Object? codes, int start, int? end) {
    RangeError.checkNotNegative(start, 'start');
    if (end != null && end < start) {
      throw RangeError.range(end, start, null, 'end');
    }
    if (end == start) return '';
    final iterator = _iterator(codes);
    for (var i = 0; i < start; i++) {
      if (!_moveNext(iterator)) return '';
    }
    final values = <int>[];
    for (var i = start; (end == null || i < end) && _moveNext(iterator); i++) {
      values.add(_current(iterator) as int);
    }
    return String.fromCharCodes(values);
  }

  Object? _current(Object iterator) => iterator is _Instance
      ? _member(iterator, 'current', .getter, [])
      : (iterator as Iterator<Object?>).current;

  Object? _add(Object? collection, Object? value) {
    if (collection is _Instance) {
      return _member(collection, 'add', .method, [value]);
    }
    if (collection is _CollectionValue) {
      _typeOperation(collection.type.typeArguments.single, value, cast: true);
      collection.checkMutable();
      collection = collection.storage;
    }
    if (collection is Set<Object?>) return collection.add(value);
    (collection as List<Object?>).add(value);
    return null;
  }

  void _put(Object? map, Object? key, Object? value) {
    if (map is _Instance) {
      _member(map, '[]=', .method, [key, value]);
      return;
    }
    if (map is _CollectionValue) {
      _typeOperation(map.type.typeArguments[0], key, cast: true);
      _typeOperation(map.type.typeArguments[1], value, cast: true);
      map.checkMutable();
      map = map.storage;
    }
    (map as Map<Object?, Object?>)[key] = value;
  }

  Object? _mapEntries(Object? source) {
    if (source is _Instance) return _member(source, 'entries', .getter, []);
    if (source is _CollectionValue) {
      final type = CoreTypes.mapEntryOf(
        source.type.typeArguments[0],
        source.type.typeArguments[1],
      );
      return _CollectionValue(
        CoreTypes.iterableOf(type),
        (source.storage as Map<Object?, Object?>).entries.map(
          (entry) => _Instance(type, this)
            ..fields[CoreTypes.mapEntryKey] = entry.key
            ..fields[CoreTypes.mapEntryValue] = entry.value,
        ),
      );
    }
    return (source as Map<Object?, Object?>).entries;
  }

  Object? _entryField(Object? entry, InstanceField field) => entry is _Instance
      ? entry.fields[field]
      : field == CoreTypes.mapEntryKey
      ? (entry as MapEntry<Object?, Object?>).key
      : (entry as MapEntry<Object?, Object?>).value;

  void _spread(
    Object? collection,
    Object? source,
    bool isMap,
    bool isMethodCall,
    bool checksMapEntries,
  ) {
    if (collection is _Instance) {
      _member(collection, 'addAll', .method, [source]);
      return;
    }
    if (collection is _CollectionValue && isMethodCall) {
      final sourceType = isMap
          ? CoreTypes.mapOf(
              collection.type.typeArguments[0],
              collection.type.typeArguments[1],
            )
          : CoreTypes.iterableOf(collection.type.typeArguments.single);
      _typeOperation(sourceType, source, cast: true);
      // The SDK rejects even empty addAll before acquiring the source iterator.
      collection.checkMutable();
    }
    if (isMap) {
      if (checksMapEntries) {
        final type = (collection as _CollectionValue).type;
        final iterator = _iterator(_mapEntries(source));
        while (_moveNext(iterator)) {
          final entry = _current(iterator);
          final key = _typeOperation(
            type.typeArguments[0],
            _entryField(entry, CoreTypes.mapEntryKey),
            cast: true,
          );
          final value = _typeOperation(
            type.typeArguments[1],
            _entryField(entry, CoreTypes.mapEntryValue),
            cast: true,
          );
          _put(collection, key, value);
        }
      } else if (source is _Instance) {
        final type = source.type.asInstanceOf(CoreTypes.map)!;
        _member(source, 'forEach', .method, [
          _NativeFunction(FunctionType(.voidType, type.typeArguments), (args) {
            _put(collection, args[0], args[1]);
            return null;
          }),
        ]);
      } else {
        final storage = source is _CollectionValue ? source.storage : source;
        (storage as Map<Object?, Object?>).forEach(
          (key, value) => _put(collection, key, value),
        );
      }
    } else {
      final iterator = _iterator(source);
      while (_moveNext(iterator)) {
        _add(collection, _current(iterator));
      }
    }
  }

  Object? run(
    IrFunction function,
    List<Object?> args, [
    Map<TypeParameterType, ValueType> environment = const {},
  ]) {
    if (function.bodyKind == .asynchronous) {
      final frame = _ExecutionFrame(
        function,
        List.of(args),
        Map.of(environment),
      );
      final type = (function.completionType!).substitute(environment);
      return _GuestFuture(CoreTypes.futureOf(type), _driveAsync(frame, type));
    }
    if (function.bodyKind == .syncGenerator) {
      final saved = List<Object?>.unmodifiable(args);
      final types = Map<TypeParameterType, ValueType>.unmodifiable(environment);
      return _GeneratorIterable(
        CoreTypes.iterableOf((function.yieldType!).substitute(types)),
        () => _GeneratorIterator(this, function, saved, types),
      );
    }
    if (function.bodyKind == .asyncGenerator) {
      return _StreamActivation(
        function,
        List.of(args),
        Map.of(environment),
      ).stream(this);
    }
    return _run(function, args, environment);
  }

  /// Observes a root guest Future without flattening a future-valued payload.
  Future<Object?> resolveAsync(Object? value) async {
    if (value is! _GuestFuture) throw StateError('Expected a guest Future.');
    return (await value.carrier).value;
  }

  Future<_FutureBox> _driveAsync(
    _ExecutionFrame frame, [
    ValueType? completion,
  ]) async {
    while (true) {
      final step = _run(
        frame.function,
        frame.arguments,
        frame.environment,
        frame,
      );
      if (step is _Returned) {
        if (completion == null) return _FutureBox(null);
        final source = _futureType(step.value);
        final awaited = _boxOrAdopt(step.value, completion, check: false);
        if (awaited is Future<_FutureBox>) return awaited;
        // A Future in the value arm still takes the SDK's async completion path.
        return source == null ? awaited : Future<_FutureBox>.value(awaited);
      }
      Jump? edge;
      if (step is _Suspended) {
        final operation = step.operation;
        final type = operation.result.type.substitute(frame.environment);
        final awaited = _boxOrAdopt(step.operand, type, check: false);
        try {
          final box = await awaited;
          frame.values[operation.result] = _typeOperation(
            type,
            box.value,
            cast: true,
          );
          edge = operation.onResume;
        } catch (error, trace) {
          if (error is _AsyncUnsupported || operation.onThrow == null) rethrow;
          frame.values[UnwindValue.exception] = error;
          frame.values[UnwindValue.stackTrace] = trace;
          edge = operation.onThrow;
        }
      } else {
        final stream = frame as _StreamActivation;
        final (end, value) = step as (Terminator, Object?);
        final (resume, cancel) = switch (end) {
          Yield(:final onResume, :final onCancel) => (onResume, onCancel!),
          YieldStream(:final onResume, :final onCancel) => (onResume, onCancel),
          _ => throw StateError('Expected a stream yield.'),
        };
        if (stream.controller.hasListener) {
          if (end is YieldStream) {
            try {
              await stream.controller.addStream(
                value as Stream<Object?>,
                cancelOnError: false,
              );
            } catch (error, trace) {
              if (end.onThrow == null) rethrow;
              frame.values[UnwindValue.exception] = error;
              frame.values[UnwindValue.stackTrace] = trace;
              edge = end.onThrow;
            }
          } else {
            stream.controller.add(value);
          }
          if (edge == null && stream.controller.hasListener) {
            await null;
            while (stream.controller.hasListener &&
                stream.controller.isPaused) {
              final wake = stream.wake = Completer<void>();
              await wake.future;
            }
          }
        }
        edge ??= stream.controller.hasListener ? resume : cancel;
      }
      if (edge == null) fail('A Never await returned');
      Object? read(Value value) => switch (value) {
        Constant() => _constant(value, frame.environment),
        TestedValue(:final test) => read(test.operand),
        _ => frame.values[value],
      };
      frame.arguments = edge.arguments.map(read).toList();
      frame.block = edge.target;
    }
  }

  Object? _run(
    IrFunction function,
    List<Object?> args,
    Map<TypeParameterType, ValueType> environment, [
    _ExecutionFrame? frame,
  ]) {
    ValueType resolve(ValueType type) => type.substitute(environment);
    final values = frame?.values ?? <Value, Object?>{};
    Object? read(Value v) => switch (v) {
      Constant() => _constant(v, environment),
      TestedValue(:final test) => read(test.operand),
      _ => values[v],
    };
    Object? checkType(ValueType type, Object? value, {required bool cast}) {
      // Reification erases promotions; a checked value must first satisfy all
      // static conjuncts, including those under a nullable or FutureOr union.
      final matches = switch (type) {
        NonNullableTypeParameterType(:final parameter) =>
          value != null && (checkType(parameter, value, cast: false) as bool),
        PromotedTypeParameterType(
          :final parameter,
          :final bound,
          :final isNonNullable,
        ) =>
          (!isNonNullable || value != null) &&
              (checkType(parameter, value, cast: false) as bool) &&
              (checkType(bound, value, cast: false) as bool),
        FutureOrType(:final argument, :final futureType) =>
          (checkType(argument, value, cast: false) as bool) ||
              (checkType(futureType, value, cast: false) as bool),
        _
            when type != type.nonNullable &&
                (type.nonNullable is PromotedTypeParameterType ||
                    type.nonNullable is FutureOrType) =>
          value == null ||
              (checkType(type.nonNullable, value, cast: false) as bool),
        _ => null,
      };
      if (matches == null) {
        return _typeOperation(resolve(type), value, cast: cast);
      }
      if (!cast) return matches;
      if (matches) return value;
      throw TypeError();
    }

    void execute(Instruction op) {
      switch (op) {
        case NewPayload() ||
            NativeView() ||
            NativeAddress() ||
            NativeSymbolAddress() ||
            NativeSize() ||
            NativeFieldOffset() ||
            CopyNative():
          throw UnsupportedError(
            'Native aggregate memory requires target execution.',
          );
        case KeepAlive():
          values[op] = null;
        case PointerFromAddress(:final address):
          values[op] = ffi.Pointer<ffi.Void>.fromAddress(read(address) as int);
        case PointerAddress(:final pointer):
          values[op] = (read(pointer) as ffi.Pointer).address;
        case PointerOffset(:final pointer, :final index):
          final size = FfiTypes.pointerElementSize(op.type)!;
          values[op] = ffi.Pointer<ffi.Void>.fromAddress(
            (read(pointer) as ffi.Pointer).address +
                (read(index) as int) * size,
          );
        case NativeCall(:final pointer, :final arguments):
          final invoke = callNative;
          if (invoke == null) {
            throw UnsupportedError(
              'Native function calls require native execution.',
            );
          }
          final address = (read(pointer) as ffi.Pointer).address;
          values[op] = invoke(op, address, arguments.map(read).toList());
        case LoadObjectData() ||
            ReferenceAddress() ||
            ReferenceFromAddress() ||
            StoreObjectData() ||
            LoadObjectReference() ||
            StoreObjectReference():
          throw UnsupportedError(
            'Managed physical storage requires native execution.',
          );
        case LoadNative(:final address, nativeType: final native):
          final data = _nativeData(
            ffi.Pointer<ffi.Void>.fromAddress(read(address) as int),
            native.nativeSize,
          );
          if (native.isFloating) {
            values[op] = native.isSinglePrecision
                ? data.getFloat32(0, Endian.host)
                : data.getFloat64(0, Endian.host);
            break;
          }
          final layout = native.integerLayout!;
          values[op] = switch (layout.bytes) {
            1 => layout.signed ? data.getInt8(0) : data.getUint8(0),
            2 =>
              layout.signed
                  ? data.getInt16(0, Endian.host)
                  : data.getUint16(0, Endian.host),
            4 =>
              layout.signed
                  ? data.getInt32(0, Endian.host)
                  : data.getUint32(0, Endian.host),
            _ => data.getInt64(0, Endian.host),
          };
        case StoreNative(
          :final address,
          nativeType: final native,
          :final value,
        ):
          final data = _nativeData(
            ffi.Pointer<ffi.Void>.fromAddress(read(address) as int),
            native.nativeSize,
          );
          if (native.isFloating) {
            final number = read(value) as double;
            if (native.isSinglePrecision) {
              data.setFloat32(0, number, Endian.host);
            } else {
              data.setFloat64(0, number, Endian.host);
            }
            break;
          }
          final integer = read(value) as int;
          switch (native.nativeSize) {
            case 1:
              data.setInt8(0, integer);
            case 2:
              data.setInt16(0, integer, Endian.host);
            case 4:
              data.setInt32(0, integer, Endian.host);
            case 8:
              data.setInt64(0, integer, Endian.host);
          }
        case ReifyType(:final template):
          values[op] = _typeValue(resolve(template));
        case ObjectHashCode(:final operand, :final direct):
          values[op] = direct
              ? identityHashCode(read(operand))
              : read(operand).hashCode;
        case ObjectRuntimeType(:final operand, :final direct):
          values[op] = direct
              ? _typeValue(_runtimeValueType(read(operand)))
              : _dynamicDispatch(
                  read(operand),
                  _selector('runtimeType', .getter),
                  const [],
                  const {},
                  const [],
                );
        case NewCollection(:final collectionType, :final growable):
          final type = resolve(collectionType) as ClassType;
          values[op] = _CollectionValue(
            type,
            type.declaration == CoreTypes.map
                ? <Object?, Object?>{}
                : type.declaration == CoreTypes.set
                ? <Object?>{}
                : List<Object?>.empty(
                    growable: growable == null || read(growable) as bool,
                  ),
          );
        case ListFilled(
          :final type,
          :final length,
          :final fill,
          :final growable,
        ):
          values[op] = _CollectionValue(
            resolve(type) as ClassType,
            List<Object?>.filled(
              read(length) as int,
              read(fill),
              growable: read(growable) as bool,
            ),
          );
        case ListFrom(:final type, :final elements, :final growable):
          final result = _CollectionValue(
            resolve(type) as ClassType,
            <Object?>[],
          );
          _spread(result, read(elements), false, false, false);
          values[op] = read(growable) as bool
              ? result
              : _CollectionValue(
                  result.type,
                  List<Object?>.of(result.storage as List, growable: false),
                );
        case CollectionAdd(:final collection, :final value):
          values[op] = _add(read(collection), read(value));
        case CollectionSpread(
          :final collection,
          :final source,
          :final isMethodCall,
          :final checksMapEntries,
        ):
          _spread(
            read(collection),
            read(source),
            CoreTypes.view(collection.type, CoreTypes.map) != null,
            isMethodCall,
            checksMapEntries,
          );
        case MapPut(:final map, :final key, :final value):
          _put(read(map), read(key), read(value));
        case GetIterator(:final iterable):
          values[op] = _iterator(read(iterable));
        case IteratorMoveNext(:final iterator):
          values[op] = _moveNext(read(iterator)!);
        case IteratorCurrent(:final iterator):
          values[op] = _current(read(iterator)!);
        case MapEntries(:final map):
          values[op] = _mapEntries(read(map));
        case CollectionLength(:final collection):
          final value = read(collection);
          final storage = value is _CollectionValue ? value.storage : value;
          values[op] = value is _Instance
              ? _member(value, 'length', .getter, [])
              : storage is Map<Object?, Object?>
              ? storage.length
              : (storage as Iterable<Object?>).length;
        case CollectionGet(:final collection, :final key):
          final value = read(collection);
          final storage = value is _CollectionValue ? value.storage : value;
          values[op] = value is _Instance
              ? _member(value, '[]', .method, [read(key)])
              : storage is Map<Object?, Object?>
              ? storage[read(key)]
              : (storage as List<Object?>)[read(key) as int];
        case ListSublist(:final list, :final start, :final end):
          final receiver = read(list);
          final arguments = [read(start), if (end != null) read(end)];
          if (receiver is _Instance) {
            values[op] = _member(receiver, 'sublist', .method, arguments);
          } else {
            final storage = receiver is _CollectionValue
                ? receiver.storage
                : receiver;
            final source = storage as List<Object?>;
            final result = end == null
                ? source.sublist(arguments[0] as int)
                : source.sublist(arguments[0] as int, arguments[1] as int?);
            values[op] = receiver is _CollectionValue
                ? _CollectionValue(
                    CoreTypes.listOf(
                      CoreTypes.view(
                        receiver.type,
                        CoreTypes.list,
                      )!.typeArguments.single,
                    ),
                    result,
                  )
                : result;
          }
        case MapContainsKey(:final map, :final key):
          final receiver = read(map);
          final storage = receiver is _CollectionValue
              ? receiver.storage
              : receiver;
          values[op] = receiver is _Instance
              ? _member(receiver, 'containsKey', .method, [read(key)])
              : (storage as Map<Object?, Object?>).containsKey(read(key));
        case PatternMatchFailure():
          throw StateError('Pattern matching error');
        case ListSet(:final collection, :final key, :final value):
          final receiver = read(collection);
          if (receiver is _Instance) {
            _member(receiver, '[]=', .method, [read(key), read(value)]);
          } else {
            if (receiver is _CollectionValue) {
              _typeOperation(
                receiver.type.typeArguments.single,
                read(value),
                cast: true,
              );
              receiver.checkMutable();
            }
            final storage = receiver is _CollectionValue
                ? receiver.storage
                : receiver;
            (storage as List<Object?>)[read(key) as int] = read(value);
          }
        case AssertionFailure(:final message):
          throw AssertionError(message == null ? null : read(message));
        case Construct(:final initializer, :final inputs):
          values[op] = _construct(
            initializer,
            inputs.map(read).toList(),
            resolve(op.type) as ClassType,
          );
        case MakeClosure(:final target, :final inputs):
          values[op] = _FunctionValue(
            target,
            null,
            inputs.map(read).toList(),
            environment,
          );
        case NewCell(:final initial, :final initializer):
          final type = op.type as CellType;
          final cell = _Cell(
            type.isLate ? resolve(type) as CellType : type,
            initial == null ? _uninitialized : read(initial),
            initializer == null ? null : read(initializer),
          );
          if (type.isLate && initial != null) {
            cell.value = _typeOperation(
              cell.type.content,
              cell.value,
              cast: true,
            );
          }
          values[op] = cell;
        case CopyCell(:final cell):
          final source = read(cell) as _Cell;
          values[op] = _Cell(source.type, source.value, source.initializer);
        case ReadCell(:final cell):
          values[op] = _loadCell(read(cell) as _Cell);
        case WriteCell(:final cell, :final value):
          _storeCell(read(cell) as _Cell, read(value));
        case BindMethod(:final method, :final receiver, :final direct):
          final instance = read(receiver);
          if (!direct && _isObjectToString(method) && instance is! _Instance) {
            values[op] = _dynamicBridge(
              instance,
              _selector('toString', .getter),
              [],
              {},
              [],
            );
            break;
          }
          if (!direct &&
              instance is _GeneratorIterator &&
              method.owner?.declaration == CoreTypes.iterator &&
              method.name == 'moveNext') {
            values[op] = _dynamicBridge(
              instance,
              _selector('moveNext', .getter),
              const [],
              const {},
              const [],
            );
            break;
          }
          if (instance is _GuestFuture || instance is _GuestCompleter) {
            throw _AsyncUnsupported('Async method tear-off');
          }
          if (instance is! _Instance) {
            throw UnsupportedError('Unmodeled fixture method tear-off');
          }
          final function = _FunctionValue(
            direct ? method : _resolveMember(instance, method),
            instance,
          );
          values[op] = _typeOperation(resolve(op.type), function, cast: true);
        case InstantiateFunction(:final function, :final typeArguments):
          final value = read(function) as _FunctionValue;
          values[op] = value.instantiate(typeArguments.map(resolve).toList());
        case MakeInvocation(
          :final selector,
          :final positional,
          :final named,
          :final typeArguments,
        ):
          values[op] = _runtimeInvocation(
            selector,
            positional.map(read).toList(),
            {for (final e in named.entries) e.key: read(e.value)},
            typeArguments.map(resolve).toList(),
            typedForwarder: true,
          );
        case DynamicDispatch(
          :final receiver,
          :final selector,
          :final positional,
          :final named,
          :final typeArguments,
        ):
          values[op] = _dynamicDispatch(
            read(receiver),
            selector,
            positional.map(read).toList(),
            {for (final e in named.entries) e.key: read(e.value)},
            typeArguments.map(resolve).toList(),
          );
        case FunctionCall(
          :final function,
          :final positional,
          :final named,
          :final typeArguments,
        ):
          values[op] = _call(read(function), positional.map(read).toList(), {
            for (final e in named.entries) e.key: read(e.value),
          }, typeArguments.map(resolve).toList());
        case LoadLibrary(:final reference):
          values[op] = _GuestFuture(
            CoreTypes.futureOf(.dynamicType),
            Future<_FutureBox>.microtask(() {
              _loadedLibraries.add(reference);
              return _FutureBox(null);
            }),
          );
        case CheckLibraryLoaded(:final reference):
          if (!_loadedLibraries.contains(reference)) throw _DeferredNotLoaded();
        case LoadGlobal(:final global):
          values[op] = _loadGlobal(global);
        case StoreGlobal(:final global, :final value):
          _storeGlobal(global, read(value));
        case StoreField(:final field, :final receiver, :final value):
          final instance = read(receiver) as _Instance;
          final type = field.type.substitute(
            instance.type.asInstanceOf(field.owner)!.typeEnvironment,
          );
          final converted = _typeOperation(type, read(value), cast: true);
          if (field.isLate && field.isFinal) {
            _bindLazy(instance.fields, field, converted, isFinal: true);
          } else {
            instance.fields[field] = converted;
          }
        case LoadField(:final field, :final receiver):
          values[op] = field.owner == CoreTypes.mapEntry
              ? _entryField(read(receiver), field)
              : field.isLate
              ? _loadLateField(read(receiver) as _Instance, field)
              : (read(receiver) as _Instance).fields[field];
          if (field.requiresReadCheck) {
            values[op] = checkType(op.type, values[op], cast: true);
          }
        case InstanceCall(
          :final typeArguments,
          :final member,
          :final receiver,
          :final positional,
          :final named,
        ):
          final value = read(receiver);
          if (value is _GuestFuture ||
              value is _GuestCompleter ||
              value is _GuestStreamIterator) {
            final actual = switch (value) {
              _GuestFuture(:final type) ||
              _GuestCompleter(:final type) ||
              _GuestStreamIterator(:final type) => type,
              _ => throw StateError('Expected an async protocol value.'),
            };
            final types = typeArguments.map(resolve).toList();
            final signature = _instantiateSignature(
              member.signatureFor(actual),
              types,
            );
            final args = signature.bind<Object?>(
              positional.map(read).toList(),
              {for (final e in named.entries) e.key: read(e.value)},
              (_) => null,
            );
            for (final (i, arg) in args.indexed) {
              _typeOperation(signature.parameters[i], arg, cast: true);
            }
            values[op] = _asyncMember(
              value!,
              member.selector,
              positional.map(read).toList(),
              {for (final e in named.entries) e.key: read(e.value)},
              types,
            );
            break;
          }
          final target = value is _Instance
              ? _resolveMember(value, member)
              : program.dispatch(
                      _runtimeValueType(value) as ClassType,
                      member,
                    ) ??
                    member;
          values[op] = _invoke(
            _FunctionValue(target, value),
            positional.map(read).toList(),
            {for (final e in named.entries) e.key: read(e.value)},
            typeArguments.map(resolve).toList(),
          );
          if (member.requiresResultCheck) {
            values[op] = checkType(op.type, values[op], cast: true);
          }
        case MakeRecord(:final type, :final inputs):
          values[op] = _RecordValue(
            resolve(type) as RecordType,
            inputs.map(read).toList(),
          );
        case RecordGet(:final record, :final slot):
          values[op] = (read(record) as _RecordValue).fields[slot];
        case TypeTest(:final operand, :final testedType, :final negated):
          values[op] =
              (checkType(testedType, read(operand), cast: false) as bool) !=
              negated;
        case TypeCast(:final operand, :final type):
          values[op] = checkType(type, read(operand), cast: true);
        case TypeView(:final operand):
          values[op] = read(operand);
        case NullCheck(:final operand):
          values[op] = read(operand)!;
        case Interpolate(:final inputs):
          final buffer = StringBuffer();
          for (final input in inputs) {
            buffer.write(read(input).toString());
          }
          values[op] = buffer.toString();
        case StringConcat(:final left, :final right):
          values[op] = (read(left) as String) + (read(right) as String);
        case StringLength(:final string):
          values[op] = (read(string) as String).length;
        case StringFromCharCode(:final code):
          values[op] = String.fromCharCode(read(code) as int);
        case StringFromCharCodes(:final codes, :final start, :final end):
          values[op] = _fromCharCodes(
            read(codes),
            read(start) as int,
            read(end) as int?,
          );
        case StringCodeUnitAt(:final string, :final index):
          values[op] = (read(string) as String).codeUnitAt(read(index) as int);
        case NumericNegate(:final operand):
          values[op] = -(read(operand) as num);
        case NumericToDouble(:final operand):
          values[op] = (read(operand) as num).toDouble();
        case FloatBitCast(:final operand, :final width):
          final bytes = ByteData(8);
          if (operand.type == .integer) {
            if (width == 32) {
              bytes.setInt32(0, read(operand) as int);
              values[op] = bytes.getFloat32(0);
            } else {
              bytes.setInt64(0, read(operand) as int);
              values[op] = bytes.getFloat64(0);
            }
          } else if (width == 32) {
            bytes.setFloat32(0, read(operand) as double);
            values[op] = bytes.getUint32(0);
          } else {
            bytes.setFloat64(0, read(operand) as double);
            values[op] = bytes.getInt64(0);
          }
        case NumericRoundToDouble(:final operand, :final rounding):
          final number = read(operand) as num;
          values[op] = switch (rounding) {
            .truncate => number.truncateToDouble(),
            .floor => number.floorToDouble(),
            .ceil => number.ceilToDouble(),
            .round => number.roundToDouble(),
          };
        case NumericToInt(:final operand, :final rounding):
          final number = read(operand) as num;
          values[op] = switch (rounding) {
            .truncate => number.toInt(),
            .floor => number.floor(),
            .ceil => number.ceil(),
            .round => number.round(),
          };
        case NumericSquareRoot(:final operand):
          values[op] = math.sqrt(read(operand) as num);
        case NumericBinary(:final operator, :final left, :final right):
          final a = read(left) as num, b = read(right) as num;
          values[op] = switch (operator) {
            .add => a + b,
            .subtract => a - b,
            .multiply => a * b,
            .divide => a / b,
            .truncateDivide => a ~/ b,
            .modulo => a % b,
            .remainder => a.remainder(b),
            .lessThan => (numericOrder(a, b) ?? 1) < 0,
            .lessOrEqual => (numericOrder(a, b) ?? 1) <= 0,
            .greaterThan => (numericOrder(a, b) ?? -1) > 0,
            .greaterOrEqual => (numericOrder(a, b) ?? -1) >= 0,
          };
        case IntBinary(:final operator, :final left, :final right):
          final a = read(left) as int, b = read(right) as int;
          values[op] = switch (operator) {
            .add => a + b,
            .subtract => a - b,
            .multiply => a * b,
            .divide => a / b,
            .truncateDivide => a ~/ b,
            .modulo => a % b,
            .remainder => a.remainder(b),
            .bitAnd => a & b,
            .bitOr => a | b,
            .bitXor => a ^ b,
            .shiftLeft => a << b,
            .shiftRight => a >> b,
            .unsignedShiftRight => a >>> b,
            .lessThan => a < b,
            .lessOrEqual => a <= b,
            .greaterThan => a > b,
            .greaterOrEqual => a >= b,
          };
        case Identical(:final left, :final right):
          values[op] = identical(read(left), read(right));
        case Equals(:final left, :final right, :final negated):
          final a = read(left), b = read(right);
          values[op] =
              (a is num && b is num ? numericOrder(a, b) == 0 : a == b) !=
              negated;
        case DirectCall(
          :final target,
          :final inputs,
          :final ownerType,
          :final typeArguments,
        ):
          final arguments = inputs.map(read).toList();
          values[op] = _enter(target, arguments, {
            ...environment,
            if (ownerType != null)
              ...(resolve(ownerType) as ClassType).typeEnvironment,
            for (final (i, parameter) in target.typeParameters.indexed)
              parameter: resolve(typeArguments[i]),
          });
          if (target.requiresResultCheck) {
            values[op] = checkType(op.type, values[op], cast: true);
          }
      }
    }

    var block = frame?.block ?? function.entry;
    args = frame?.arguments ?? args;
    for (var steps = 0; steps < 1000; steps++) {
      for (final (i, p) in block.parameters.indexed) {
        values[p] = args[i];
      }
      block.instructions.forEach(execute);
      final end = block.end;
      Jump? edge;
      Jump? handler;
      try {
        switch (end) {
          case Return(:final value):
            if (frame is _GeneratorIterator) return frame.complete();
            final result = value == null ? null : read(value);
            return frame == null ? result : _Returned(result);
          case Await():
            if (frame == null || frame is _GeneratorIterator) {
              fail('Await in an ordinary activation');
            }
            return _Suspended(end, read(end.operand));
          case Yield(:final value, :final onResume):
            if (frame is _StreamActivation) return (end, read(value));
            if (frame is! _GeneratorIterator) {
              fail('Yield in an ordinary activation');
            }
            frame
              .._current = read(value)
              ..arguments = onResume.arguments.map(read).toList()
              ..block = onResume.target;
            return true;
          case YieldStream(:final stream):
            return (end, read(stream));
          case Invoke(:final operation, :final onReturn, :final onThrow):
            handler = onThrow;
            execute(operation);
            edge = onReturn;
          case Throw(:final exception, :final stackTrace, :final onThrow):
            handler = onThrow;
            final error = read(exception)!;
            if (stackTrace != null) {
              Error.throwWithStackTrace(error, read(stackTrace) as StackTrace);
            }
            throw error;
          case Unreachable():
            fail('Reached a Never continuation');
          case ExhaustivenessFailure():
            fail('Exhaustive fixture had no matching case');
          case Jump():
            edge = end;
          case Branch():
            edge = read(end.condition) as bool ? end.ifTrue : end.ifFalse;
        }
      } catch (exception, trace) {
        if (exception is _AsyncUnsupported || handler == null) rethrow;
        values[UnwindValue.exception] = exception;
        values[UnwindValue.stackTrace] = trace;
        edge = handler;
      }
      if (edge == null) fail('A Never operation returned');
      args = edge.arguments.map(read).toList();
      block = edge.target;
    }
    fail(
      'Fixture did not return in 1000 block visits: ${function.target.name}',
    );
  }
}

final class _GeneratorIterable(
  final ClassType type,
  final Iterator<Object?> Function() _createIterator,
) extends Iterable<Object?> {
  @override
  Iterator<Object?> get iterator => _createIterator();
}

base class _ExecutionFrame(
  final IrFunction function,
  var List<Object?> arguments,
  final Map<TypeParameterType, ValueType> environment,
) {
  final values = <Value, Object?>{};
  Block block = function.entry;
}

final class _StreamActivation(
  super.function,
  super.arguments,
  super.environment,
) extends _ExecutionFrame {
  final controller = StreamController<Object?>(sync: true);
  Completer<void>? wake;

  Stream<Object?> stream(IrInterpreter runner) {
    final done = Completer<void>();
    void resume() {
      wake?.complete();
      wake = null;
    }

    controller.onListen = () => scheduleMicrotask(() async {
      try {
        await runner._driveAsync(this);
      } catch (error, trace) {
        if (controller.hasListener) {
          controller.addError(error, trace);
        } else {
          done.completeError(error, trace);
        }
      } finally {
        if (!done.isCompleted) done.complete();
        unawaited(controller.close());
      }
    });
    controller.onResume = resume;
    controller.onCancel = () {
      resume();
      return controller.isClosed ? null : done.future;
    };
    return controller.stream;
  }
}

final class _Returned(final Object? value);
final class _Suspended(final Await operation, final Object? operand);
final class _FutureBox(final Object? value);

final class _GuestStreamIterator(
  final ClassType type,
  final StreamIterator<Object?> iterator,
);

final class _GuestFuture(
  final ClassType type,
  final Future<_FutureBox> carrier,
) {
  @override
  String toString() =>
      throw _AsyncUnsupported('Concrete Future string representation');
}

final class _GuestCompleter(final ClassType type, bool synchronous) {
  final Completer<_FutureBox> completer = synchronous
      ? Completer<_FutureBox>.sync()
      : Completer<_FutureBox>();
  late final _GuestFuture future = _GuestFuture(
    CoreTypes.futureOf(type.typeArguments.single),
    completer.future,
  );
  @override
  String toString() =>
      throw _AsyncUnsupported('Concrete Completer string representation');
}

// Capability failures must not be mistaken for catchable Dart program errors.
final class _AsyncUnsupported(super.message) extends UnsupportedError;

final class _DeferredNotLoaded() extends Error;

ClassType? _futureType(Object? value) => switch (value) {
  _GuestFuture(:final type) => type,
  _Instance(:final type) => CoreTypes.view(type, CoreTypes.future),
  Future() => throw _AsyncUnsupported('Native Future runtime bridge'),
  _ => null,
};

FutureOr<_FutureBox> _boxOrAdopt(
  Object? value,
  ValueType type, {
  bool check = true,
}) {
  if (check) _typeOperation(ValueType.futureOr(type), value, cast: true);
  final actual = _futureType(value);
  if (actual != null && CoreTypes.futureOf(type).accepts(actual)) {
    if (value is! _GuestFuture) {
      throw _AsyncUnsupported('User-defined Future await/adoption');
    }
    return value.carrier;
  }
  return _FutureBox(value);
}

final class _GeneratorIterator(
  final IrInterpreter runner,
  super.function,
  super.arguments,
  super.environment,
) extends _ExecutionFrame implements Iterator<Object?> {
  late final ClassType type = CoreTypes.iteratorOf(
    (function.yieldType!).substitute(environment),
  );
  Object? _current;
  bool _done = false, _running = false;

  @override
  Object? get current =>
      _typeOperation(type.typeArguments.single, _current, cast: true);

  bool complete() {
    _done = true;
    _current = null;
    values.clear();
    return false;
  }

  @override
  bool moveNext() {
    if (_running) {
      throw UnsupportedError('Reentrant fixture generator activation');
    }
    if (_done) return false;
    _running = true;
    try {
      return runner._run(function, arguments, environment, this) as bool;
    } catch (_) {
      complete();
      rethrow;
    } finally {
      _running = false;
    }
  }
}

Object? _typeOperation(ValueType type, Object? value, {required bool cast}) {
  if (type == ValueType.dynamicType) return cast ? value : true;
  Object? run<T>() => cast ? value as T : value is T;
  Object? scalar<T>() => type == type.nonNullable ? run<T>() : run<T?>();
  final actual = switch (value) {
    ffi.Pointer() => FfiTypes.pointerRuntimeType,
    _TypeValue() => ValueType.typeType,
    _Instance(:final type) => type,
    _CollectionValue(:final type) => type,
    _GeneratorIterable(:final type) ||
    _GeneratorIterator(:final type) ||
    _GuestFuture(:final type) ||
    _GuestStreamIterator(:final type) ||
    _GuestCompleter(:final type) => type,
    _NativeFunction(:final signature) => signature,
    _FunctionValue() => value.reifiedSignature,
    _ => null,
  };
  if (actual != null || type.nonNullable is FunctionType) {
    final ok = actual != null
        ? type.accepts(actual)
        : value == null && type.accepts(.nullType);
    if (!cast) return ok;
    if (!ok) throw TypeError();
    return value;
  }
  if (type.nonNullable case final RecordType target) {
    final ok = value == null
        ? type.accepts(.nullType)
        : value is _RecordValue &&
              target.sameShape(value.type) &&
              target.fields.indexed.every(
                (p) =>
                    _typeOperation(p.$2, value.fields[p.$1], cast: false)
                        as bool,
              );
    if (!cast) return ok;
    if (ok) return value;
    throw TypeError();
  }
  if (type.nonNullable == .record) {
    final ok =
        value is _RecordValue ||
        value is Record ||
        (value == null && type.accepts(.nullType));
    if (!cast) return ok;
    if (ok) return value;
    throw TypeError();
  }
  if (type.nonNullable case FutureOrType(:final argument, :final futureType)) {
    final ok = value == null
        ? type.accepts(.nullType)
        : (_typeOperation(argument, value, cast: false) as bool) ||
              (_typeOperation(futureType, value, cast: false) as bool);
    if (!cast) return ok;
    if (ok) return value;
    throw TypeError();
  }
  if (value is Future &&
      CoreTypes.view(type.nonNullable, CoreTypes.future) != null) {
    throw _AsyncUnsupported('Native Future runtime type checks');
  }
  if (type == .nullType) return run<Null>();
  if (type.nonNullable == CoreTypes.exception) return scalar<Exception>();
  if (type.nonNullable == CoreTypes.integerDivisionByZeroException) {
    // ignore: deprecated_member_use
    return scalar<IntegerDivisionByZeroException>();
  }
  return switch (type.nonNullable) {
    ValueType.integer => scalar<int>(),
    ValueType.floating => scalar<double>(),
    ValueType.number => scalar<num>(),
    ValueType.string => scalar<String>(),
    ValueType.boolean => scalar<bool>(),
    ValueType.object => scalar<Object>(),
    ValueType.function => scalar<Function>(),
    ValueType.error => scalar<Error>(),
    ValueType.typeError => scalar<TypeError>(),
    ValueType.noSuchMethodError => scalar<NoSuchMethodError>(),
    ValueType.assertionError => scalar<AssertionError>(),
    ValueType.argumentError => scalar<ArgumentError>(),
    ClassType(:final library, name: 'RangeError')
        when library == Uri.parse('dart:core') =>
      scalar<RangeError>(),
    ValueType.stateError => scalar<StateError>(),
    ValueType.unsupportedError => scalar<UnsupportedError>(),
    ValueType.stackTrace => scalar<StackTrace>(),
    ValueType.never => run<Never>(),
    ValueType.voidType => cast ? value : true,
    ClassType() =>
      cast
          ? (value == null && type.accepts(.nullType)
                ? null
                : throw TypeError())
          : value == null && type.accepts(.nullType),
    _ => throw StateError('Unexpected fixture type ${type.dartName}'),
  };
}

// Trigger the host runtime's private LateError rather than inventing a public
// error type or replacing it with StateError. These helpers always throw.
final class _LateRead() {
  late Object? value;
}

Object? _lateWriteError() {
  late final Object? value;
  void bind() => value = null;
  bind();
  bind();
  return value;
}

final _uninitialized = Object();

void _checkLazyBind(bool boundFinal) {
  if (boundFinal) _lateWriteError();
}

final class _Cell(
  final CellType type,
  var Object? value, [
  final Object? initializer,
]);

/// Dart type identity is structural equality, not mutual assignability.
final class _TypeValue(final ValueType representedType) {
  @override
  bool operator ==(Object other) =>
      other is _TypeValue && representedType == other.representedType;

  @override
  int get hashCode => representedType.hashCode;

  @override
  String toString() => representedType.dartName;
}

final class _FunctionValue(
  final FunctionTarget target, [
  final Object? receiver,
  final List<Object?> captures = const [],
  final Map<TypeParameterType, ValueType> environment = const {},
  final List<ValueType>? typeArguments,
  final _FunctionValue? genericOrigin,
  final FunctionType? constructorSignature,
  final (Uri, String)? constructorAlias,
  final List<ValueType>? constructorTypeArguments,
]) {
  FunctionType get genericSignature =>
      constructorSignature ??
      target.tearOffSignature(
        reified: true,
        ownerType:
            (target.kind == .initializer || target.kind == .factory) &&
                target.owner!.typeParameters.every(environment.containsKey)
            ? (target.owner!).substitute(environment) as ClassType
            : null,
      );

  _FunctionValue instantiate(List<ValueType> arguments) {
    _instantiateSignature(reifiedSignature, arguments);
    return _FunctionValue(
      target,
      receiver,
      captures,
      environment,
      arguments,
      genericOrigin ?? this,
      constructorSignature,
      constructorAlias,
      constructorTypeArguments,
    );
  }

  FunctionType get reifiedSignature {
    final signature = genericSignature.substitute({
      ...environment,
      if (receiver != null)
        ...(_runtimeValueType(receiver) as ClassType)
            .asInstanceOf(target.owner!)!
            .typeEnvironment,
    }) as FunctionType;
    return typeArguments == null
        ? signature
        : _instantiateSignature(signature, typeArguments!);
  }

  bool get isConstructor =>
      target.kind == .initializer || target.kind == .factory;

  Map<TypeParameterType, ValueType> get identityEnvironment => {
    ...environment,
    if (isConstructor && typeArguments != null)
      ...(reifiedSignature.result as ClassType).typeEnvironment,
  }.map((parameter, type) => MapEntry(parameter, type.normalize()));

  List<ValueType>? get identityTypeArguments =>
      isConstructor && constructorAlias == null
      ? null
      : typeArguments?.map((type) => type.normalize()).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FunctionValue &&
          (target.kind != .closure ||
              genericOrigin != null &&
                  identical(genericOrigin, other.genericOrigin)) &&
          target == other.target &&
          constructorAlias == other.constructorAlias &&
          identical(receiver, other.receiver) &&
          _sameTypes(identityTypeArguments, other.identityTypeArguments) &&
          identityEnvironment.length == other.identityEnvironment.length &&
          identityEnvironment.entries.every(
            (entry) => other.identityEnvironment[entry.key] == entry.value,
          );
  @override
  int get hashCode => target.kind == .closure && genericOrigin == null
      ? identityHashCode(this)
      : Object.hash(
          target,
          constructorAlias,
          identityHashCode(target.kind == .closure ? genericOrigin : receiver),
          identityTypeArguments == null
              ? null
              : Object.hashAll(identityTypeArguments!),
          Object.hashAllUnordered(
            identityEnvironment.entries.map(
              (entry) => Object.hash(entry.key, entry.value),
            ),
          ),
        );
}

final class _Instance(final ClassType type, final IrInterpreter runner) {
  final fields = <InstanceField, Object?>{};

  static final _equality = FunctionTarget(
    ValueType.object.library,
    '==',
    .boolean,
    [.object],
    owner: ValueType.object,
    kind: .method,
  );

  @override
  bool operator ==(Object other) {
    if (type == CoreTypes.symbolStorage) {
      return other is _Instance &&
          other.type == CoreTypes.symbolStorage &&
          fields[CoreTypes.symbolName] == other.fields[CoreTypes.symbolName] &&
          fields[CoreTypes.symbolPrivateLibrary] ==
              other.fields[CoreTypes.symbolPrivateLibrary];
    }
    final target = runner.program.dispatch(type, _equality);
    return target == null
        ? identical(this, other)
        : runner._invoke(_FunctionValue(target, this), [other], const {})
              as bool;
  }

  static final _string = FunctionTarget(
    ValueType.object.library,
    'toString',
    .string,
    [],
    owner: ValueType.object,
    kind: .method,
  );

  String get defaultString => "Instance of '${type.dartName}'";

  @override
  String toString() {
    if (type == CoreTypes.symbolStorage) {
      return Symbol(fields[CoreTypes.symbolName] as String).toString();
    }
    final target = runner.program.dispatch(type, _string);
    return target == null
        ? defaultString
        : runner._invoke(_FunctionValue(target, this), [], const {}) as String;
  }

  static final _hash = FunctionTarget(
    ValueType.object.library,
    'hashCode',
    .integer,
    [],
    owner: ValueType.object,
    kind: .getter,
  );

  @override
  int get hashCode {
    if (type == CoreTypes.symbolStorage) {
      final name = fields[CoreTypes.symbolName] as String;
      final library = fields[CoreTypes.symbolPrivateLibrary] as String?;
      return library == null
          ? Symbol(name).hashCode
          : Object.hash(name, library);
    }
    final target = runner.program.dispatch(type, _hash);
    return target == null
        ? identityHashCode(this)
        : runner._invoke(_FunctionValue(target, this), [], const {}) as int;
  }
}

final class _RecordValue(final RecordType type, final List<Object?> fields) {
  @override
  bool operator ==(Object other) =>
      other is _RecordValue &&
      type.sameShape(other.type) &&
      fields.indexed.every((p) => p.$2 == other.fields[p.$1]);

  @override
  int get hashCode => Object.hashAll(fields);

  @override
  String toString() {
    final parts = <String>[];
    for (var i = 0; i < type.positionalCount; i++) {
      parts.add(fields[i].toString());
    }
    for (final entry in type.slots.entries.skip(type.positionalCount)) {
      parts.add('${entry.key}: ${fields[entry.value]}');
    }
    return '(${parts.join(', ')})';
  }
}

final class _CollectionValue(
  final ClassType type,
  final Object storage, {
  final bool immutable = false,
}) {
  void checkMutable() {
    if (immutable) {
      throw UnsupportedError('Cannot modify a constant collection');
    }
  }

  @override
  String toString() => storage.toString();
}

final class _NativeFunction(
  final FunctionType signature,
  final Object? Function(List<Object?>) callback, [
  final (Object?, MemberSelector)? binding,
]) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      binding != null &&
          other is _NativeFunction &&
          other.binding != null &&
          identical(binding!.$1, other.binding!.$1) &&
          binding!.$2 == other.binding!.$2;
  @override
  int get hashCode => binding == null
      ? identityHashCode(this)
      : Object.hash(identityHashCode(binding!.$1), binding!.$2);
}

// Native errors retain this adapter without reading user Invocation getters.
// Only diagnostic rendering needs these conversions; represented generic types
// cannot be expressed as host Type objects and are omitted from that rendering.
final class _GuestInvocation(final IrInterpreter runner, final Object value)
    implements Invocation {
  Object? read(String name) => runner._dynamicDispatch(
    value,
    IrInterpreter._selector(name, .getter),
    const [],
    const {},
    const [],
  );
  Object? storage(Object? value) =>
      value is _CollectionValue ? value.storage : value;
  @override
  Symbol get memberName {
    final symbol = read('memberName') as _Instance;
    return Symbol(symbol.fields[CoreTypes.symbolName] as String);
  }

  @override
  List<Type> get typeArguments => const [];
  @override
  List<dynamic> get positionalArguments =>
      (storage(read('positionalArguments')) as List).toList();
  @override
  Map<Symbol, dynamic> get namedArguments => {
    for (final e in (storage(read('namedArguments')) as Map).entries)
      Symbol((e.key as _Instance).fields[CoreTypes.symbolName] as String):
          e.value,
  };
  @override
  bool get isMethod => read('isMethod') as bool;
  @override
  bool get isGetter => read('isGetter') as bool;
  @override
  bool get isSetter => read('isSetter') as bool;
  @override
  bool get isAccessor => read('isAccessor') as bool;
}

bool _sameTypes(List<ValueType>? left, List<ValueType>? right) =>
    left == null || right == null
    ? left == right
    : left.length == right.length &&
          left.indexed.every((entry) => entry.$2 == right[entry.$1]);

FunctionType _instantiateSignature(
  FunctionType signature,
  List<ValueType> arguments,
) {
  try {
    return signature.instantiate(arguments);
  } on ArgumentError {
    throw TypeError();
  }
}

final _noDynamicBridge = Object();

ValueType _runtimeValueType(Object? value) => switch (value) {
  ffi.Pointer() => FfiTypes.pointerRuntimeType,
  null => ValueType.nullType,
  _Instance(:final type) => type,
  _CollectionValue(:final type) when type.declaration == CoreTypes.list => type,
  _CollectionValue() => throw UnsupportedError(
    'Unmodeled concrete collection runtime type',
  ),
  _GuestFuture() || _GuestCompleter() => throw _AsyncUnsupported(
    'Unmodeled concrete async runtime type',
  ),
  _GeneratorIterable() || _GeneratorIterator() => throw UnsupportedError(
    'Unmodeled concrete generator runtime type',
  ),
  _RecordValue(:final type) => type,
  _FunctionValue() => value.reifiedSignature,
  _NativeFunction(:final signature) => signature,
  _TypeValue() => ValueType.typeType,
  bool() => ValueType.boolean,
  int() => ValueType.integer,
  double() => ValueType.floating,
  String() => ValueType.string,
  NoSuchMethodError() => ValueType.noSuchMethodError,
  TypeError() => throw UnsupportedError(
    'Unmodeled concrete TypeError runtime type',
  ),
  StateError() => ValueType.stateError,
  // ignore: deprecated_member_use
  IntegerDivisionByZeroException() => CoreTypes.integerDivisionByZeroException,
  UnsupportedError() => ValueType.unsupportedError,
  AssertionError() ||
  Error() => throw UnsupportedError('Unmodeled concrete error runtime type'),
  _ => throw UnsupportedError('Unmodeled fixture runtime type'),
};
