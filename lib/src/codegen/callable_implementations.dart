import 'package:dartc/ir.dart';

import 'closure_storage.dart';
import 'type_implementations.dart';

/// Owns demanded function-value calling shapes and their typed execution entries.
///
/// Function storage and language identity do not demand executable entries. Only
/// actual calls create adapters; retain this owner across compiler graph changes.
final class CallableImplementations({final TypeImplementations? types}) {
  final _shapes = <Object, CallEntryShape>{};
  final _functions = <(FunctionTarget, CallEntryShape), IrFunction>{};
  final _adapters = <FunctionTarget>{};
  final _slots = <int, CallEntryShape>{};
  var _nextSlot = 0;
  final _declarations = <FunctionTarget, IrCallable>{};
  var _revision = 0;
  ClosureStorage? _storage;
  final _constructions = <FunctionTarget, IrFunction>{};
  final _instantiations = <Object, IrFunction>{};
  final _bindings = <Object, IrFunction>{};
  final _methodEntries =
      <
        (
          FunctionTarget,
          FunctionType,
          ExecutionSignature,
          ValueType,
          ValueType,
        ),
        IrFunction
      >{};
  ExecutionShapes _executionShapes = ExecutionShapes.defaults;
  final _entryExecutions = <FunctionTarget, ExecutionSignature>{};

  /// Explicit physical contracts for the actual adapter bodies.
  Map<FunctionTarget, ExecutionSignature> get entryExecutions =>
      Map.unmodifiable(_entryExecutions);

  ExecutionShapes get _entryShapes => ExecutionShapes(
    entries: {..._executionShapes.entries, ..._entryExecutions},
    slots: _executionShapes.slots,
  );

  /// Common physical contracts including entries installed by this owner.
  ExecutionShapes get executionShapes => _entryShapes;
  Iterable<IrFunction> get constructionFunctions => [
    ..._constructions.values,
    ..._instantiations.values,
    ..._bindings.values,
    ..._methodEntries.values,
  ];
  ClosureStorage get storage =>
      _storage ??
      (throw StateError('Callable storage requires registered declarations.'));

  int get revision => _revision;
  Iterable<CallEntryShape> get shapes => _shapes.values;
  Iterable<IrFunction> get functions => _functions.values;
  bool ownsAdapter(FunctionTarget target) => _adapters.contains(target);

  /// Declared defaults are storage metadata, independent of body reachability.
  void extend(IrProgram program) {
    _executionShapes = program.executionShapes ?? ExecutionShapes.defaults;
    _storage ??= ClosureStorage(
      const [],
      definitions: [...program.functions, ...program.externals],
      storageDeclarations: program.classes,
      callableImplementations: this,
    );
    storage.registerDeclarations([...program.functions, ...program.externals]);
    for (final body in [...program.functions, ...program.externals]) {
      _declarations[body.target] = body;
    }
    // A rewritten graph carries its actual execution contract. Repreparing it
    // must not regenerate adapters and discard their existing checks or effects.
    for (final body in program.functions) {
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation case BindMethod(entryBinding: final binding?)) {
            binding.checkExecution(_executionShapes);
            for (final entry in binding.entries.entries) {
              final body = program.implementationOf(entry.value);
              if (body is! IrFunction)
                throw StateError('A method producer needs its actual body.');
              _methodEntries[(
                    entry.key,
                    binding.signature,
                    binding.execution,
                    operation.type,
                    operation.receiver.type,
                  )] =
                  body;
              _entryExecutions[entry.value] = binding.execution;
            }
          }
          if (operation
              case FunctionCall(entryBinding: final binding?) ||
                  DynamicDispatch(entryBinding: final binding?)) {
            binding.checkExecution(_executionShapes);
            final previous = _slots[binding.shape.slot];
            if (previous != null && !identical(previous, binding.shape)) {
              throw StateError('Conflicting callable entry slot declarations.');
            }
            _slots[binding.shape.slot] = binding.shape;
            if (_nextSlot <= binding.shape.slot) {
              _nextSlot = binding.shape.slot + 1;
            }
            for (final entry in binding.entries.entries) {
              final implementation = program.implementationOf(entry.value);
              if (implementation is! IrFunction) {
                throw StateError(
                  'A callable execution entry requires its typed body.',
                );
              }
              final previous = _functions[(entry.key, binding.shape)];
              if (previous != null && previous.target != entry.value) {
                throw StateError(
                  'A callable source has conflicting entries for one slot.',
                );
              }
              _functions[(entry.key, binding.shape)] = implementation;
              _entryExecutions[entry.value] = binding.shape.execution;
              _adapters.add(entry.value);
            }
          }
        }
      }
    }
  }

  /// Expands closure creation into actual fields and the shared construction op.
  IrFunction closureConstruction(FunctionTarget source) =>
      _constructions.putIfAbsent(source, () {
        final shape = storage.ensureClosure(source);
        final target = FunctionTarget(
          null,
          'createClosure',
          source.signature,
          shape.captures.map((field) => field.type),
          typeParameters: source.capturedTypeParameters,
        );
        final entry = Block(target.parameterTypes);
        final args = <Value>[
          entry.emit(FunctionEntryTableAddress(source)),
          for (final (index, input) in entry.parameters.indexed)
            input.type == shape.captures[index].type
                ? input
                : entry.emit(TypeView(input, shape.captures[index].type)),
          for (final parameter in shape.parameters)
            entry.emit(
              UncheckedCast(
                entry.emit(ReifyType(parameter)),
                TypeMetadata.type,
              ),
            ),
        ];
        entry.finish(
          Return(
            entry.emit(
              Construct.callable(
                shape.storage,
                args,
                source.signature,
                entry.emit(ReifyType(source.signature)),
              ),
            ),
          ),
        );
        _revision++;
        return IrFunction(target, [entry]);
      });

  DirectCall createClosure(MakeClosure operation) {
    final body = closureConstruction(operation.target);
    return DirectCall(body.target, [
      for (final (index, value) in operation.inputs.indexed)
        value.type is CellType
            ? CellReference(value)
            : value.type == body.target.signature.parameters[index]
            ? value
            : TypeView(value, body.target.signature.parameters[index]),
    ], typeArguments: operation.target.capturedTypeParameters);
  }

  DirectCall instantiateFunction(InstantiateFunction operation) {
    final types =
        this.types ??
        (throw StateError(
          'Function instantiation requires the shared type implementation owner.',
        ));
    final signature = operation.function.type as FunctionType;
    final key = (
      signature,
      operation.typeArguments.fold<Object?>(null, (key, type) => (key, type)),
    );
    final body = _instantiations.putIfAbsent(key, () {
      final parameters = <TypeParameterType>{
        ...signature.freeTypeParameters,
        for (final type in operation.typeArguments) ...type.freeTypeParameters,
      }.toList();
      final target = FunctionTarget(
        null,
        'instantiateFunction',
        operation.type,
        [signature],
        typeParameters: parameters,
      );
      final entry = Block(target.parameterTypes);
      Value arguments = const Constant.nullValue();
      for (final type in operation.typeArguments.reversed) {
        final descriptor = entry.emit(
          UncheckedCast(entry.emit(ReifyType(type)), TypeMetadata.type),
        );
        arguments = entry.emit(types.values.cons(descriptor, arguments));
      }
      final metadata = entry.emit(
        UncheckedCast(
          entry.emit(ObjectRuntimeType(entry.parameters.single, direct: true)),
          TypeMetadata.type,
        ),
      );
      final actual = entry.emit(
        DirectCall(types.values.entry(.typeInstantiate), [metadata, arguments]),
      );
      entry.finish(
        Return(
          entry.emit(
            Construct.callable(
              storage.instantiated,
              [entry.parameters.single, arguments],
              operation.type,
              actual,
            ),
          ),
        ),
      );
      _revision++;
      return IrFunction(target, [entry]);
    });
    return DirectCall(body.target, [
      operation.function,
    ], typeArguments: body.target.typeParameters);
  }

  DirectCall instantiateFunctionFrom(InstantiateFunctionFrom operation) {
    final types =
        this.types ??
        (throw StateError(
          'Function instantiation requires the shared type implementation owner.',
        ));
    final signature = operation.function.type as FunctionType;
    final key = (signature, operation.instance.type, operation.declaration);
    final body = _instantiations.putIfAbsent(key, () {
      final parameters = <TypeParameterType>{
        ...signature.freeTypeParameters,
        ...operation.instance.type.freeTypeParameters,
      }.toList();
      final target = FunctionTarget(
        null,
        'instantiateFromInstance',
        .function,
        [signature, operation.instance.type],
        typeParameters: parameters,
      );
      final entry = Block(target.parameterTypes);
      final instance = entry.emit(
        UncheckedCast(
          entry.emit(ObjectRuntimeType(entry.parameters[1], direct: true)),
          TypeMetadata.type,
        ),
      );
      Value arguments = const Constant.nullValue();
      for (
        var index = operation.declaration.typeParameters.length - 1;
        index >= 0;
        index--
      ) {
        final projected = entry.emit(
          DirectCall(types.relations.argumentOf(operation.declaration, index), [
            instance,
          ]),
        );
        final descriptor = entry.emit(NullCheck(projected));
        arguments = entry.emit(types.values.cons(descriptor, arguments));
      }
      final metadata = entry.emit(
        UncheckedCast(
          entry.emit(ObjectRuntimeType(entry.parameters.first, direct: true)),
          TypeMetadata.type,
        ),
      );
      final actual = entry.emit(
        DirectCall(types.values.entry(.typeInstantiate), [metadata, arguments]),
      );
      entry.finish(
        Return(
          entry.emit(
            Construct.callable(
              storage.instantiated,
              [entry.parameters.first, arguments],
              .function,
              actual,
            ),
          ),
        ),
      );
      _revision++;
      return IrFunction(target, [entry]);
    });
    return DirectCall(body.target, [
      operation.function,
      operation.instance,
    ], typeArguments: body.target.typeParameters);
  }

  DirectCall bindMethod(
    BindMethod operation,
    Map<ClassType, FunctionTarget> targets,
  ) {
    final body = _methodBody(operation, targets);
    return DirectCall(body.target, [
      operation.receiver,
    ], typeArguments: body.target.typeParameters);
  }

  /// Produces one selected method using the caller's complete physical contract.
  FunctionTarget methodEntry(
    BindMethod operation,
    FunctionTarget source,
    FunctionType signature,
    ExecutionSignature execution,
  ) {
    if (_declarations[source] == null || source.isAbstract) {
      throw StateError(
        'A method producer requires its actual source declaration.',
      );
    }
    return _methodEntries.putIfAbsent(
      (source, signature, execution, operation.type, operation.receiver.type),
      () {
        final body = _methodBody(
          operation,
          const {},
          selected: source,
          signature: signature,
          execution: execution,
        );
        _entryExecutions[body.target] = execution;
        return body;
      },
    ).target;
  }

  IrFunction _methodBody(
    BindMethod operation,
    Map<ClassType, FunctionTarget> targets, {
    FunctionTarget? selected,
    FunctionType? signature,
    ExecutionSignature? execution,
  }) {
    final types =
        this.types ??
        (throw StateError(
          'Method extraction requires the shared type implementation owner.',
        ));
    final byDeclaration = <ClassType, FunctionTarget>{};
    for (final entry in targets.entries) {
      final previous = byDeclaration[entry.key.declaration];
      if (previous != null && previous != entry.value) {
        throw StateError('Conflicting method selection for one declaration.');
      }
      byDeclaration[entry.key.declaration] = entry.value;
    }
    final key = (
      operation.method,
      operation.direct,
      operation.receiver.type,
      operation.type,
      selected,
      signature,
      execution,
      byDeclaration.entries.fold<Object?>(
        null,
        (key, entry) => (key, entry.key, entry.value),
      ),
    );
    final body = _bindings.putIfAbsent(key, () {
      final parameters = <TypeParameterType>{
        ...operation.receiver.type.freeTypeParameters,
        ...operation.type.freeTypeParameters,
      }.toList();
      final target = FunctionTarget(
        null,
        'bindMethod',
        signature?.result ?? operation.type,
        [
          if (signature == null)
            operation.receiver.type
          else
            ...signature.parameters,
        ],
        typeParameters: signature == null ? parameters : const [],
      );
      final entry = Block(target.parameterTypes);
      final blocks = [entry];
      final raw = <TypeParameterType, Value>{
        if (signature != null)
          for (final (index, parameter) in parameters.indexed)
            parameter: entry.parameters[index + 1],
      };
      final bindings = [
        for (final parameter in raw.keys)
          TypeBinding.checked(
            entry.emit(CheckedTypeArgument(parameter, raw[parameter]!, raw)),
          ),
      ];
      final receiver =
          operation.receiver.type.accepts(entry.parameters.first.type)
          ? entry.parameters.first
          : entry.emit(
              TypeCast(entry.parameters.first, operation.receiver.type),
            );
      final actual = entry.emit(
        UncheckedCast(
          entry.emit(ObjectRuntimeType(receiver, direct: true)),
          TypeMetadata.type,
        ),
      );
      void construct(Block block, FunctionTarget method) {
        final shape = storage.ensureMethod(method);
        final environment = <TypeParameterType, Value>{};
        for (final (index, parameter) in method.owner!.typeParameters.indexed) {
          final descriptor = block.emit(
            DirectCall(types.relations.argumentOf(method.owner!, index), [
              actual,
            ]),
          );
          environment[parameter] = block.emit(NullCheck(descriptor));
        }
        final metadata = types.values.build(
          block,
          method.reifiedSignature,
          environment,
          shift: (value, count) => block.emit(
            DirectCall(types.values.entry(.typeShift), [
              value,
              Constant.integer(count),
              const Constant.integer(0),
            ]),
          ),
        );
        final producedType = method.reifiedSignature.freeTypeParameters.isEmpty
            ? method.reifiedSignature
            : ValueType.function;
        final value = block.emit(
          Construct.callable(
            shape.storage,
            [
              block.emit(FunctionEntryTableAddress(method)),
              receiver,
              for (final parameter in shape.parameters) environment[parameter]!,
            ],
            producedType,
            metadata,
          ),
        );
        block.finish(
          Return(
            block.emit(
              operation.type.accepts(producedType)
                  ? TypeView(value, operation.type)
                  : TypeCast(value, operation.type),
            ),
          ),
        );
      }

      if (selected != null || operation.direct) {
        construct(entry, selected ?? operation.method);
      } else {
        final shape = entry.emit(LoadField(TypeMetadata.shape, actual));
        var current = entry;
        for (final target in byDeclaration.entries) {
          final selected = Block(), next = Block();
          blocks.addAll([selected, next]);
          current.finish(
            Branch(
              current.emit(
                Equals(shape, Constant.integer(types.values.id(target.key))),
              ),
              Jump(selected),
              Jump(next),
            ),
          );
          construct(selected, target.value);
          current = next;
        }
        // A receiver outside the observed nominal implementations cannot supply
        // a compatible tear-off. Keep the real checked failure in typed IR.
        current.finish(
          Return(
            current.emit(TypeCast(const Constant.nullValue(), operation.type)),
          ),
        );
      }
      _revision++;
      return IrFunction(
        target,
        blocks,
        typeBindings: bindings,
        execution: execution == null
            ? null
            : FunctionExecution({
                for (final (index, parameter) in entry.parameters.indexed)
                  parameter: execution.parameters[index],
              }),
      );
    });
    return body;
  }

  FunctionTarget dynamicMethodBinding(FunctionTarget method) {
    final key = (method, 'dynamicMethod');
    return _bindings.putIfAbsent(key, () {
      final target = FunctionTarget(null, 'extractMethod', .dynamicType, [
        .dynamicType,
      ]);
      final entry = Block(target.parameterTypes);
      final owner = method.owner!;
      final view = owner == ValueType.nullClass
          ? ValueType.nullType
          : owner.instantiate([
              for (final _ in owner.typeParameters) ValueType.dynamicType,
            ]);
      final receiver = entry.emit(TypeCast(entry.parameters.single, view));
      final bound = entry.emit(
        bindMethod(BindMethod(method, receiver, direct: true), const {}),
      );
      entry.finish(Return(bound));
      _revision++;
      return IrFunction(target, [entry]);
    }).target;
  }

  /// Entries actually demanded for [target], possibly empty for stored values.
  Map<CallEntryShape, FunctionTarget> entriesFor(FunctionTarget target) => {
    for (final entry in _functions.entries)
      if (entry.key.$1 == target) entry.key.$2: entry.value.target,
  };

  /// Captures the actual caller's components independently of semantic types.
  CallEntryShape shapeOf(FunctionCall call, {required IrFunction caller}) =>
      _shapeOf(
        call,
        call.type,
        call.positional,
        call.named,
        call.typeArguments.length,
        caller: caller,
      );

  CallEntryShape _shapeOf(
    Instruction operation,
    ValueType resultType,
    List<Value> values,
    Map<String, Value> namedValues,
    int typeArgumentCount, {
    FunctionTarget? failure,
    required IrFunction caller,
  }) {
    // Adapters are closed ordinary functions. Free lexical types remain checked
    // inside their source entry; this widening does not choose a physical shape.
    ValueType closed(ValueType type) =>
        type.freeTypeParameters.isEmpty ? type : ValueType.object.nullable;
    final result = closed(resultType);
    final positional = values.map((value) => closed(value.type)).toList();
    final names = namedValues.keys.toList()..sort();
    final named = {
      for (final name in names) name: closed(namedValues[name]!.type),
    };
    final execution = ExecutionSignature([
      ExecutionShape.reference,
      for (final value in values) _executionShapes.shapeOf(caller, value),
      for (final name in names)
        _executionShapes.shapeOf(caller, namedValues[name]!),
      for (var i = 0; i < typeArgumentCount; i++) ExecutionShape.reference,
    ], _executionShapes.shapeOf(caller, operation));
    Object sequence(Iterable<Object> values) =>
        values.fold<Object>((), (key, value) => (key, value));
    final key = (
      result,
      sequence(positional),
      sequence(named.entries.map((entry) => (entry.key, entry.value))),
      typeArgumentCount,
      failure,
      sequence(namedValues.keys),
      execution,
    );
    return _shapes.putIfAbsent(key, () {
      _revision++;
      final shape = CallEntryShape(
        _nextSlot++,
        result,
        positional,
        named: named,
        typeArgumentCount: typeArgumentCount,
        checked: failure != null,
        failure: failure,
        failureNamed: failure == null ? const [] : namedValues.keys,
        execution: execution,
      );
      _slots[shape.slot] = shape;
      return shape;
    });
  }

  /// Gives an existing call complete typed entries for its actual source targets.
  CallEntryBinding bind(
    FunctionCall call,
    Iterable<FunctionTarget> targets, {
    required IrFunction caller,
  }) {
    if (call.entryBinding case final binding?) {
      return CallEntryBinding(binding.shape, {
        ...binding.entries,
        for (final target in targets)
          target:
              binding.entries[target] ?? _entry(target, binding.shape).target,
      }, executionShapes: _entryShapes);
    }
    final shape = shapeOf(call, caller: caller);
    return CallEntryBinding(shape, {
      for (final target in targets) target: _entry(target, shape).target,
    }, executionShapes: _entryShapes);
  }

  CallEntryBinding bindDynamic(
    DynamicDispatch call,
    Iterable<FunctionTarget> targets, {
    required IrFunction caller,
  }) {
    final failure =
        call.failure ??
        (throw StateError(
          'Dynamic callable checks need normalized failure behavior.',
        ));
    final shape =
        call.entryBinding?.shape ??
        _shapeOf(
          call,
          call.type,
          call.positional,
          call.named,
          call.typeArguments.length,
          failure: failure,
          caller: caller,
        );
    return CallEntryBinding(shape, {
      ...?call.entryBinding?.entries,
      for (final target in targets) target: _entry(target, shape).target,
    }, executionShapes: _entryShapes);
  }

  IrFunction _entry(
    FunctionTarget source,
    CallEntryShape shape,
  ) => _functions.putIfAbsent((source, shape), () {
    final signature = source.signature;
    if (!shape.checked &&
        shape.typeArgumentCount != 0 &&
        shape.typeArgumentCount != source.typeParameters.length) {
      throw UnsupportedError(
        'Generic callable entry environment: ${source.name}',
      );
    }
    final target = FunctionTarget(
      null,
      'callEntry${_functions.length}',
      shape.result,
      shape.signature.parameters,
    );
    final entry = Block(target.parameterTypes);
    _entryExecutions[target] = shape.execution;
    if (shape.checked &&
        (!signature.acceptsShape(shape.positional.length, shape.named.keys) ||
            shape.typeArgumentCount != 0 &&
                shape.typeArgumentCount != source.typeParameters.length)) {
      final raw = <TypeParameterType, Value>{
        for (final (index, parameter) in shape.failure!.typeParameters.indexed)
          parameter:
              entry.parameters[1 +
                  shape.positional.length +
                  shape.named.length +
                  index],
      };
      final bindings = [
        for (final parameter in raw.keys)
          TypeBinding.checked(
            entry.emit(CheckedTypeArgument(parameter, raw[parameter]!, raw)),
          ),
      ];
      final failed = entry.emit(
        DirectCall(shape.failure!, [
          entry.parameters.first,
          ...entry.parameters.skip(1).take(shape.positional.length),
          for (final name in shape.failureNamed)
            entry.parameters[1 +
                shape.positional.length +
                shape.named.keys.toList().indexOf(name)],
        ], typeArguments: shape.failure!.typeParameters),
      );
      entry.finish(Return(failed));
      _adapters.add(target);
      _revision++;
      return IrFunction(target, [entry], typeBindings: bindings);
    }
    final captured = source.capturedTypeParameters;
    final parameters = [...captured, ...source.typeParameters];
    final blocks = [entry];
    var current = entry;
    final raw = <TypeParameterType, Value>{
      for (final parameter in captured)
        parameter: entry.emit(
          ReadFunctionTypeArgument(entry.parameters.first, source, parameter),
        ),
    };
    if (shape.checked &&
        shape.typeArgumentCount == 0 &&
        source.typeParameters.isNotEmpty) {
      final types =
          this.types ??
          (throw StateError(
            'Default generic arguments need actual type metadata.',
          ));
      storage.requirePrefix();
      final callable = entry.emit(TypeCast(entry.parameters.first, .function));
      final prefix = entry.emit(CallableReference(callable));
      final stored = entry.emit(LoadField(FunctionStorage.arguments, prefix));
      final defaults = Block(),
          bound = Block(),
          join = Block([
            for (final _ in source.typeParameters) TypeMetadata.type,
          ]);
      blocks.addAll([defaults, bound, join]);
      entry.finish(
        Branch(
          entry.emit(Equals(stored, const Constant.nullValue())),
          Jump(defaults),
          Jump(bound),
        ),
      );
      final values = <Value>[];
      for (final type in source.signature.defaultTypeArguments) {
        values.add(
          types.values.build(
            defaults,
            type,
            raw,
            shift: (value, count) => defaults.emit(
              DirectCall(types.values.entry(.typeShift), [
                value,
                Constant.integer(count),
                const Constant.integer(0),
              ]),
            ),
          ),
        );
      }
      defaults.finish(Jump(join, values));
      bound.finish(
        Jump(join, [
          for (final parameter in source.typeParameters)
            bound.emit(
              ReadFunctionTypeArgument(
                entry.parameters.first,
                source,
                parameter,
              ),
            ),
        ]),
      );
      for (final (index, parameter) in source.typeParameters.indexed) {
        raw[parameter] = join.parameters[index];
      }
      current = join;
    } else {
      for (final (index, parameter) in source.typeParameters.indexed) {
        raw[parameter] = shape.typeArgumentCount == 0
            ? entry.emit(
                ReadFunctionTypeArgument(
                  entry.parameters.first,
                  source,
                  parameter,
                ),
              )
            : entry.parameters[1 +
                  shape.positional.length +
                  shape.named.length +
                  index];
      }
    }
    final bindings = <TypeBinding>[
      for (final parameter in parameters)
        TypeBinding.checked(
          current.emit(CheckedTypeArgument(parameter, raw[parameter]!, raw)),
        ),
    ];
    final applied = signature.instantiate(source.typeParameters);
    final supplied = <Value>[];
    final named = <String, Value>{};
    Value checked(Value value, ValueType type) =>
        type.accepts(value.type) ? value : current.emit(TypeCast(value, type));
    for (var i = 0; i < shape.positional.length; i++) {
      supplied.add(checked(entry.parameters[i + 1], applied.parameters[i]));
    }
    for (final (i, name) in shape.named.keys.indexed) {
      named[name] = checked(
        entry.parameters[1 + supplied.length + i],
        applied.parameters[applied.named[name]!.slot],
      );
    }
    final body = _declarations[source];
    if (body == null) {
      throw StateError('Missing callable declaration: ${source.name}');
    }
    final invoked = current.emit(
      DirectCall(
        source,
        [
          if (source.kind == .closure || source.kind.isVirtual)
            current.emit(
              ReadFunctionEnvironment(entry.parameters.first, source),
            ),
          for (var i = 0; i < source.captures.length; i++)
            current.emit(
              ReadFunctionEnvironment(
                entry.parameters.first,
                source,
                capture: i,
              ),
            ),
          ...applied.bind<Value>(
            supplied,
            named,
            (slot) => body.defaults[slot]!,
          ),
        ],
        typeArguments: source.typeParameters,
        ownerType: source.kind.isVirtual ? source.owner : null,
        lexicalEnvironment: {
          if (source.kind == .closure)
            for (final parameter in captured) parameter: parameter,
        },
      ),
    );
    // A wider callable view cannot give a non-returning source a normal exit.
    // Keep its state and unwinding effects at the original invocation point.
    if (invoked.type == .never) {
      current.finish(Unreachable(invoked));
    } else {
      final result = shape.result == invoked.type
          ? invoked
          : current.emit(
              shape.result.accepts(invoked.type)
                  ? TypeView(invoked, shape.result)
                  : TypeCast(invoked, shape.result),
            );
      current.finish(
        result.type == .never ? Unreachable(result) : Return(result),
      );
    }
    final adapter = IrFunction(target, blocks, typeBindings: bindings);
    _adapters.add(target);
    _revision++;
    return adapter;
  });
}
