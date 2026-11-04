import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final class FixtureRunner(
  final IrProgram program,
  final Map<(Uri, String), Object? Function(int)> imports,
) {
  final bodies = {for (final f in program.functions) f.target: f};

  final _staticFunctions = <(FunctionTarget, ClassType?), _FunctionValue>{};

  Object? _constant(
    Constant value, [
    Map<TypeParameterType, ValueType> environment = const {},
  ]) => switch (value) {
    ScalarConstant(:final value) => value,
    FunctionConstant(:final target, :final ownerType) =>
      _staticFunctions.putIfAbsent(
        (
          target,
          ownerType == null
              ? null
              : substituteType(ownerType, environment) as ClassType,
        ),
        () => _FunctionValue(
          target,
          null,
          const [],
          ownerType == null
              ? const {}
              : (substituteType(
                  ownerType,
                  environment,
                ) as ClassType).typeEnvironment,
        ),
      ),
    RecordConstant(:final type, :final fields) => _RecordValue(
      type as RecordType,
      fields.map((field) => _constant(field, environment)).toList(),
    ),
  };

  Object? _enter(
    FunctionTarget target,
    List<Object?> arguments, [
    Map<TypeParameterType, ValueType> environment = const {},
  ]) {
    if (target.kind.hasReceiver) {
      environment = (arguments.first as _Instance).type
          .asInstanceOf(target.owner!)!
          .typeEnvironment;
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
    if (init.owner != ValueType.object) _enter(init, [instance, ...arguments]);
    return instance;
  }

  Object? _invoke(
    _FunctionValue fn,
    List<Object?> positional,
    Map<String, Object?> named,
  ) {
    var target = fn.target;
    var environment =
        fn.receiver?.type.asInstanceOf(target.owner!)?.typeEnvironment ??
        fn.environment;
    if (target.kind == .initializer || target.kind == .factory) {
      final resolved = target.resolveConstruction(
        substituteType(target.owner!, environment) as ClassType,
      );
      target = resolved.target;
      environment = resolved.ownerType.typeEnvironment;
    }
    final signature =
        substituteType(target.signature, environment) as FunctionType;
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
            if (target.kind == .closure) fn,
            ...fn.captures,
            ?fn.receiver,
            ...arguments,
          ], environment);
  }

  Object? _call(
    Object? function,
    List<Object?> positional,
    Map<String, Object?> named,
  ) => switch (function) {
    _FunctionValue() => _invoke(function, positional, named),
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
      map = map.storage;
    }
    (map as Map<Object?, Object?>)[key] = value;
  }

  void _spread(Object? collection, Object? source, bool isMap) {
    if (collection is _Instance) {
      _member(collection, 'addAll', .method, [source]);
      return;
    }
    if (isMap) {
      if (source is _Instance) {
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
        case CollectionSpread(:final collection, :final source):
          _spread(
            read(collection),
            read(source),
            CoreTypes.view(collection.type, CoreTypes.map) != null,
          );
        case MapPut(:final map, :final key, :final value):
          _put(read(map), read(key), read(value));
        case GetIterator(:final iterable):
          values[op] = _iterator(read(iterable));
        case IteratorMoveNext(:final iterator):
          values[op] = _moveNext(read(iterator)!);
        case IteratorCurrent(:final iterator):
          values[op] = _current(read(iterator)!);
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
        case NewCell(:final initial):
          values[op] = _Cell(initial == null ? _uninitialized : read(initial));
        case CopyCell(:final cell):
          values[op] = _Cell((read(cell) as _Cell).value);
        case ReadCell(:final cell):
          final value = (read(cell) as _Cell).value;
          if (identical(value, _uninitialized)) {
            fail('Read of an uninitialized definite-assignment local');
          }
          values[op] = value;
        case WriteCell(:final cell, :final value):
          (read(cell) as _Cell).value = read(value);
        case BindMethod(:final method, :final receiver, :final direct):
          final instance = read(receiver) as _Instance;
          values[op] = _FunctionValue(
            direct ? method : program.dispatch(instance.type, method)!,
            instance,
          );
        case FunctionCall(:final function, :final positional, :final named):
          values[op] = _call(read(function), positional.map(read).toList(), {
            for (final e in named.entries) e.key: read(e.value),
          });
        case StoreField(:final field, :final receiver, :final value):
          final instance = read(receiver) as _Instance;
          final type = substituteType(
            field.type,
            instance.type.asInstanceOf(field.owner)!.typeEnvironment,
          );
          instance.fields[field] = _typeOperation(
            type,
            read(value),
            cast: true,
          );
        case LoadField(:final field, :final receiver):
          values[op] = (read(receiver) as _Instance).fields[field];
        case InstanceCall(
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
        case DirectCall(:final target, :final inputs, :final ownerType):
          final arguments = inputs.map(read).toList();
          values[op] = _enter(
            target,
            arguments,
            ownerType == null
                ? environment
                : (resolve(ownerType) as ClassType).typeEnvironment,
          );
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
  Object? run<T>() => cast ? value as T : value is T;
  Object? scalar<T>() => type == type.nonNullable ? run<T>() : run<T?>();
  final actual = switch (value) {
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

final _uninitialized = Object();

final class _Cell(var Object? value);

final class _FunctionValue(
  final FunctionTarget target, [
  final _Instance? receiver,
  final List<Object?> captures = const [],
  final Map<TypeParameterType, ValueType> environment = const {},
]) {
  FunctionType get reifiedSignature => substituteType(
    target.reifiedSignature,
    receiver?.type.asInstanceOf(target.owner!)?.typeEnvironment ?? environment,
  ) as FunctionType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      target.kind != .closure &&
          other is _FunctionValue &&
          target == other.target &&
          identical(receiver, other.receiver) &&
          environment.length == other.environment.length &&
          environment.entries.every(
            (entry) => other.environment[entry.key] == entry.value,
          );
  @override
  int get hashCode => target.kind == .closure
      ? identityHashCode(this)
      : Object.hash(
          target,
          identityHashCode(receiver),
          Object.hashAllUnordered(
            environment.entries.map(
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

final class _CollectionValue(final ClassType type, final Object storage) {
  @override
  String toString() => storage.toString();
}

final class _NativeFunction(
  final FunctionType signature,
  final Object? Function(List<Object?>) callback,
);
