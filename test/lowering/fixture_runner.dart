import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final class FixtureRunner(
  final IrProgram program,
  final Map<(Uri, String), Object? Function(int)> imports,
) {
  final bodies = {for (final f in program.functions) f.target: f};

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

  _TypeValue _typeValue(ValueType type) =>
      _types.putIfAbsent(type, () => _TypeValue(type));

  // Canonical keys describe IR data, never runtime user equality or hashCode.
  Constant _resolvedConstant(
    Constant value,
    Map<TypeParameterType, ValueType> environment,
  ) {
    if (environment.isEmpty) return value;
    ValueType resolve(ValueType type) => substituteType(type, environment);
    Constant child(Constant value) => _resolvedConstant(value, environment);
    return switch (value) {
      ScalarConstant() || TypeConstant() => value,
      FunctionConstant() => FunctionConstant(
        value.target,
        ownerType: value.ownerType == null
            ? null
            : resolve(value.ownerType!) as ClassType,
        typeArguments: value.typeArguments?.map(resolve),
        constructorSignature: value.constructorSignature == null
            ? null
            : resolve(value.constructorSignature!) as FunctionType,
        constructorAlias: value.constructorAlias,
      ),
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
      ) =>
        _staticFunctions.putIfAbsent(
          constantKey(value),
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
          ),
        ),
      RecordConstant(:final type, :final fields) => _constants.putIfAbsent(
        constantKey(value),
        () => _RecordValue(
          type as RecordType,
          fields.map((field) => _constant(field)).toList(),
        ),
      ),
      SequenceConstant(:final type, :final elements) => _constants.putIfAbsent(
        constantKey(value),
        () => _CollectionValue(
          type as ClassType,
          type.declaration == CoreTypes.set
              ? elements.map((element) => _constant(element)).toSet()
              : elements.map((element) => _constant(element)).toList(),
          immutable: true,
        ),
      ),
      MapConstant(:final type, :final entries) => _constants.putIfAbsent(
        constantKey(value),
        () => _CollectionValue(type as ClassType, {
          for (final e in entries) _constant(e.$1): _constant(e.$2),
        }, immutable: true),
      ),
      ObjectConstant(:final type, :final fields) => _constants.putIfAbsent(
        constantKey(value),
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
        ...(arguments.first as _Instance).type
            .asInstanceOf(target.owner!)!
            .typeEnvironment,
      };
    }
    if (target.library.toString() == 'dart:core' &&
        target.name == 'identical') {
      return identical(arguments[0], arguments[1]);
    }
    final body = bodies[target];
    return body != null
        ? run(body, arguments, environment)
        : imports[(target.library, target.name)]!(arguments.single as int);
  }

  _Instance _construct(
    FunctionTarget init,
    List<Object?> arguments, [
    ClassType? instantiatedType,
  ]) {
    final instance = _Instance(instantiatedType ?? init.owner!, this);
    if (init.owner == CoreTypes.mapEntry) {
      instance.fields[CoreTypes.mapEntryKey] = arguments[0];
      instance.fields[CoreTypes.mapEntryValue] = arguments[1];
    } else if (init.owner != ValueType.object) {
      _enter(init, [instance, ...arguments]);
    }
    return instance;
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
        ...fn.receiver!.type.asInstanceOf(target.owner!)!.typeEnvironment,
    };
    final argumentsForTypes = fn.typeArguments ?? typeArguments;
    final binders = fn.genericSignature.typeParameters;
    final genericSignature =
        substituteType(fn.genericSignature, environment) as FunctionType;
    final appliedSignature = _instantiateSignature(
      genericSignature,
      argumentsForTypes,
    );
    environment = {
      ...environment,
      for (final (i, parameter) in binders.indexed)
        parameter: argumentsForTypes[i],
    };
    if (target.kind == .initializer || target.kind == .factory) {
      final resolved = target.resolveConstruction(
        appliedSignature.result as ClassType,
      );
      target = resolved.target;
      environment = {...environment, ...resolved.ownerType.typeEnvironment};
    }
    final declaredSignature =
        substituteType(target.signature, environment) as FunctionType;
    final signature = declaredSignature.typeParameters.isEmpty
        ? declaredSignature
        : _instantiateSignature(declaredSignature, argumentsForTypes);
    final arguments = signature.bind<Object?>(
      positional,
      named,
      (i) => _constant(bodies[target]!.defaults[i]!, environment),
    );
    for (final (i, arg) in arguments.indexed) {
      _typeOperation(signature.parameters[i], arg, cast: true);
    }
    return target.kind == .initializer
        ? _construct(
            target,
            arguments,
            substituteType(target.owner!, environment) as ClassType,
          )
        : _enter(target, [
            if (target.kind == .closure) fn.genericOrigin ?? fn,
            ...fn.captures,
            ?fn.receiver,
            ...arguments,
          ], environment);
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
    final member = FunctionTarget(
      instance.type.library,
      name,
      .voidType,
      [for (final _ in arguments) ValueType.object.nullable],
      owner: instance.type,
      kind: kind,
    );
    final target = program.dispatch(instance.type, member)!;
    return _invoke(_FunctionValue(target, instance), arguments, const {});
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
    ValueType resolve(ValueType type) => substituteType(type, environment);
    final values = <Value, Object?>{};
    Object? read(Value v) => switch (v) {
      Constant() => _constant(v, environment),
      TestedValue(:final test) => read(test.operand),
      _ => values[v],
    };
    void execute(Instruction op) {
      switch (op) {
        case ReifyType(:final template):
          values[op] = _typeValue(resolve(template));
        case ObjectHashCode(:final operand):
          values[op] = read(operand).hashCode;
        case NewCollection(:final collectionType):
          final type = resolve(collectionType) as ClassType;
          values[op] = _CollectionValue(
            type,
            type.declaration == CoreTypes.map
                ? <Object?, Object?>{}
                : type.declaration == CoreTypes.set
                ? <Object?>{}
                : <Object?>[],
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
          final instance = read(receiver) as _Instance;
          final function = _FunctionValue(
            direct ? method : program.dispatch(instance.type, method)!,
            instance,
          );
          values[op] = _typeOperation(resolve(op.type), function, cast: true);
        case InstantiateFunction(:final function, :final typeArguments):
          final value = read(function) as _FunctionValue;
          values[op] = value.instantiate(typeArguments.map(resolve).toList());
        case FunctionCall(
          :final function,
          :final positional,
          :final named,
          :final typeArguments,
        ):
          values[op] = _call(read(function), positional.map(read).toList(), {
            for (final e in named.entries) e.key: read(e.value),
          }, typeArguments.map(resolve).toList());
        case LoadGlobal(:final global):
          values[op] = _loadGlobal(global);
        case StoreGlobal(:final global, :final value):
          _storeGlobal(global, read(value));
        case StoreField(:final field, :final receiver, :final value):
          final instance = read(receiver) as _Instance;
          final type = substituteType(
            field.type,
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
        case InstanceCall(
          :final typeArguments,
          :final member,
          :final receiver,
          :final positional,
          :final named,
        ):
          final instance = read(receiver) as _Instance;
          final target = program.dispatch(instance.type, member)!;
          values[op] = _invoke(
            _FunctionValue(target, instance),
            positional.map(read).toList(),
            {for (final e in named.entries) e.key: read(e.value)},
            typeArguments.map(resolve).toList(),
          );
        case MakeRecord(:final type, :final inputs):
          values[op] = _RecordValue(
            resolve(type) as RecordType,
            inputs.map(read).toList(),
          );
        case RecordGet(:final record, :final slot):
          values[op] = (read(record) as _RecordValue).fields[slot];
        case TypeTest(:final operand, :final testedType, :final negated):
          values[op] =
              (_typeOperation(resolve(testedType), read(operand), cast: false)
                  as bool) !=
              negated;
        case TypeCast(:final operand, :final type):
          values[op] = _typeOperation(resolve(type), read(operand), cast: true);
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
        case NumericNegate(:final operand):
          values[op] = -(read(operand) as num);
        case NumericBinary(:final operator, :final left, :final right):
          final a = read(left) as num, b = read(right) as num;
          values[op] = switch (operator) {
            .add => a + b,
            .subtract => a - b,
            .multiply => a * b,
            .divide => a / b,
            .truncateDivide => a ~/ b,
            .modulo => a % b,
            .lessThan => a < b,
            .lessOrEqual => a <= b,
            .greaterThan => a > b,
            .greaterOrEqual => a >= b,
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
        case Equals(:final left, :final right, :final negated):
          values[op] = (read(left) == read(right)) != negated;
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
      }
    }

    var block = function.entry;
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
            return value == null ? null : read(value);
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
        if (handler == null) rethrow;
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

Object? _typeOperation(ValueType type, Object? value, {required bool cast}) {
  if (type == ValueType.dynamicType) return cast ? value : true;
  Object? run<T>() => cast ? value as T : value is T;
  Object? scalar<T>() => type == type.nonNullable ? run<T>() : run<T?>();
  final actual = switch (value) {
    _TypeValue() => ValueType.typeType,
    _Instance(:final type) => type,
    _CollectionValue(:final type) => type,
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
  if (type == .nullType) return run<Null>();
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
    ValueType.assertionError => scalar<AssertionError>(),
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
  final _Instance? receiver,
  final List<Object?> captures = const [],
  final Map<TypeParameterType, ValueType> environment = const {},
  final List<ValueType>? typeArguments,
  final _FunctionValue? genericOrigin,
  final FunctionType? constructorSignature,
  final (Uri, String)? constructorAlias,
]) {
  FunctionType get genericSignature =>
      constructorSignature ??
      target.tearOffSignature(
        reified: true,
        ownerType:
            (target.kind == .initializer || target.kind == .factory) &&
                target.owner!.typeParameters.every(environment.containsKey)
            ? substituteType(target.owner!, environment) as ClassType
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
    );
  }

  FunctionType get reifiedSignature {
    final signature = substituteType(genericSignature, {
      ...environment,
      if (receiver != null)
        ...receiver!.type.asInstanceOf(target.owner!)!.typeEnvironment,
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
  };

  List<ValueType>? get identityTypeArguments =>
      isConstructor && constructorAlias == null ? null : typeArguments;

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

final class _Instance(final ClassType type, final FixtureRunner runner) {
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

  @override
  String toString() {
    final target = runner.program.dispatch(type, _string);
    return target == null
        ? "Instance of '${type.dartName}'"
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
  final Object? Function(List<Object?>) callback,
);

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
