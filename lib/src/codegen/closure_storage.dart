import 'package:dartc/ir.dart';

import 'value_carrier.dart';
import 'callable_implementations.dart';

/// Assigns function-value storage, call entries and shared capture layouts.
final class ClosureStorage(
  Iterable<IrCallable> selectedBodies, {
  Iterable<FunctionTarget> boundMethods = const [],
  Iterable<IrCallable>? definitions,
  Iterable<FunctionConstant> storedFunctions = const [],
  Iterable<IrClass> storageDeclarations = const [],
  CallableImplementations? callableImplementations,
}) {
  final implementations = callableImplementations ?? CallableImplementations();
  final _base = FunctionStorage.type;
  final entryTable = FunctionStorage.entries;

  /// The original capture carrier, independent of language identity anchors.
  final environment = FunctionStorage.environment;
  final identity = FunctionStorage.identity;
  final identityAnchor = FunctionStorage.anchor;
  final identityArguments = FunctionStorage.arguments;
  final closures = <FunctionTarget, ClosureShape>{};
  final constants = <Object, ClosureShape>{};
  final methods = <FunctionTarget, ClosureShape>{};
  final _identities = <Object, int>{};
  final _classes = <IrClass>[];
  final _functions = <IrFunction>[];
  final _declarations = <FunctionTarget, IrCallable>{};
  var _hasBase = false;
  CallableStorage? _instantiated;

  /// The already declared common wrapper, without creating storage on inspection.
  CallableStorage? get instantiatedStorage => _instantiated;

  /// One wrapper layout for every applied function, preserving its environment.
  CallableStorage get instantiated {
    if (_instantiated case final storage?) return storage;
    _includeBase();
    final owner = ClassType(null, 'InstantiatedFunction', superclass: _base);
    final origin = InstanceField(owner, 'origin', .function, isFinal: true);
    final initializer = _initialize(owner, [
      origin,
      identityArguments,
    ], identityOrigin: origin);
    final storage = _instantiated = CallableStorage(
      type: owner,
      initializer: initializer,
      origin: origin,
    );
    _classes.add(
      IrClass(
        owner,
        [origin],
        constructors: [initializer],
        callableStorage: storage,
      ),
    );
    return storage;
  }

  Iterable<IrClass> get classes => _classes;
  Iterable<IrFunction> get functions => _functions;

  /// Refreshes declaration metadata without changing already materialized fields.
  void registerDeclarations(Iterable<IrCallable> bodies) {
    for (final body in bodies) {
      _declarations[body.target] = body;
    }
  }

  /// Demands only the actual closure's capture layout.
  ClosureShape ensureClosure(FunctionTarget target) {
    _includeBase();
    return closures.putIfAbsent(
      target,
      () => _include(
        target,
        target.signature,
        target.typeParameters,
        _defaultsOf(target),
      ),
    );
  }

  /// Demands the selected method's receiver and descriptor storage.
  ClosureShape ensureMethod(FunctionTarget target) {
    _includeBase();
    return methods.putIfAbsent(
      target,
      () => _include(
        target,
        target.reifiedSignature,
        target.typeParameters,
        _defaultsOf(target),
      ),
    );
  }

  this {
    final bodies = selectedBodies.toList();
    _declarations.addAll({
      for (final body in definitions ?? bodies) body.target: body,
    });
    for (final declaration in storageDeclarations) {
      if (declaration.callableStorage case final storage?
          when storage.source == null) {
        if (_instantiated != null && !identical(_instantiated, storage)) {
          throw StateError('Conflicting common function wrapper storage.');
        }
        _instantiated = storage;
        _includeBase();
        _classes.add(declaration);
        final body = _declarations[storage.initializer];
        if (body is! IrFunction) {
          throw StateError('Missing callable initializer body.');
        }
        _functions.add(body);
      }
      if (declaration.callableStorage case final storage?
          when storage.source != null) {
        final source = storage.source!;
        _includeBase();
        final shape = ClosureShape(
          target: source,
          sourceTarget: source,
          signature: storage.signature!,
          typeArguments: source.typeParameters,
          defaults: _defaultsOf(source),
          type: storage.type,
          initializer: storage.initializer,
          identity: storage.declarationIdentity!,
          captures: storage.captures,
          parameters: storage.parameters,
          environment: storage.descriptors,
          storage: storage,
        );
        if (source.kind == .closure) closures[source] = shape;
        if (source.kind.isVirtual) methods[source] = shape;
        _identities[source] = storage.declarationIdentity!;
        _classes.add(declaration);
        if (storage.initializer case final initializer?) {
          final body = _declarations[initializer];
          if (body is! IrFunction) {
            throw StateError('Missing callable initializer body.');
          }
          _functions.add(body);
        }
      }
    }
    final targets = <FunctionTarget>{};
    for (final body in bodies) {
      if (body.target.kind == .closure) targets.add(body.target);
      for (final block in body is IrFunction ? body.blocks : <Block>[]) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation case MakeClosure(:final target)) targets.add(target);
        }
      }
    }
    final values = {
      for (final value in storedFunctions) value.structuralKey: value,
      for (final body in bodies)
        for (final value in body.functionConstants) value.structuralKey: value,
    };
    if (targets.isNotEmpty || values.isNotEmpty || boundMethods.isNotEmpty) {
      _includeBase();
    }
    for (final target in targets) {
      closures.putIfAbsent(
        target,
        () => _include(
          target,
          target.signature,
          target.typeParameters,
          _defaultsOf(target),
        ),
      );
    }
    values.values.forEach(ensureConstant);
    for (final target in boundMethods) {
      methods.putIfAbsent(
        target,
        () => _include(
          target,
          target.reifiedSignature,
          target.typeParameters,
          _defaultsOf(target),
        ),
      );
    }
  }

  /// Declares the common prefix used by a checked entry.
  void requirePrefix() => _includeBase();

  void _includeBase() {
    if (_hasBase) return;
    _hasBase = true;
    _classes.add(
      IrClass(_base, [
        entryTable,
        environment,
        identity,
        identityAnchor,
        identityArguments,
      ]),
    );
  }

  Map<int, Constant> _defaultsOf(FunctionTarget target) {
    if (_declarations[target] case final body?) return body.defaults;
    final signature = target.signature;
    if (signature.optionalPositional == 0 &&
        signature.named.values.every((parameter) => parameter.required)) {
      return const {};
    }
    throw StateError('Missing callable defaults: ${target.name}');
  }

  /// Registers language storage without retaining an executable function body.
  ///
  /// Descriptor headers can discover constants after initial preparation. Each
  /// carrier is new; existing layouts and demanded execution entries are fixed.
  ClosureShape ensureConstant(FunctionConstant value) =>
      constants.putIfAbsent(value.structuralKey, () {
        _includeBase();
        final original =
            value.constructorAlias == null &&
                value.constructorSignature?.typeParameters.isNotEmpty == true
            ? value.target.tearOffSignature(ownerType: value.ownerType)
            : value.constructorSignature;
        final signature = original == null
            ? value.type as FunctionType
            : value.typeArguments == null
            ? original
            : original.instantiate(value.typeArguments!);
        final constructor =
            value.target.kind == .initializer || value.target.kind == .factory;
        if (constructor && value.invocationEntry == null) {
          throw StateError(
            'Constructor function values must be lowered before storage.',
          );
        }
        final target = value.invocationEntry ?? value.target.implementation;
        final defaults = _defaultsOf(target);
        List<ValueType> arguments =
            value.typeArguments ??
            (value.invocationEntry == null
                ? target.typeParameters
                : signature.typeParameters);
        if (value.constructorTypeArguments case final types?
            when value.invocationEntry == null) {
          arguments = [
            for (final type in types)
              type.substitute({
                for (final (i, parameter)
                    in value.constructorSignature!.typeParameters.indexed)
                  parameter:
                      value.typeArguments?[i] ?? signature.typeParameters[i],
              }),
          ];
        }
        return _include(
          target,
          signature,
          arguments,
          defaults,
          identity: (value.target, value.constructorAlias),
          sourceTarget: value.target,
          identityArguments:
              constructor &&
                  value.constructorAlias == null &&
                  signature.typeParameters.isEmpty
              ? (signature.result as ClassType).typeArguments
              : value.typeArguments ?? const [],
        );
      });

  ClosureShape _include(
    FunctionTarget target,
    FunctionType signature,
    List<ValueType> typeArguments,
    Map<int, Constant> defaults, {
    Object? identity,
    FunctionTarget? sourceTarget,
    List<ValueType> identityArguments = const [],
  }) {
    final index = closures.length + constants.length + methods.length;
    final owner = ClassType(null, 'Closure$index', superclass: _base);
    final captures = [
      if (target.kind.isVirtual)
        InstanceField(owner, 'receiver', .object.nullable, isFinal: true),
      for (final (i, type) in target.captures.indexed)
        InstanceField(owner, 'capture$i', _stored(type), isFinal: true),
    ];
    final parameters = target.capturedTypeParameters;
    final environment = [
      for (var i = 0; i < parameters.length; i++)
        InstanceField(owner, 'type$i', TypeMetadata.type, isFinal: true),
    ];
    final fields = [...captures, ...environment];
    final declarationIdentity = _identities.putIfAbsent(
      identity ?? target,
      () => _identities.values.fold(
        0,
        (next, value) => value >= next ? value + 1 : next,
      ),
    );
    final initializer = target.kind == .closure || target.kind.isVirtual
        ? _initialize(
            owner,
            [entryTable, ...fields],
            declarationIdentity: declarationIdentity,
            anchorField: target.kind.isVirtual ? captures.single : null,
            selfAnchor: target.kind == .closure,
          )
        : null;
    final shape = ClosureShape(
      target: target,
      sourceTarget: sourceTarget ?? target,
      signature: signature,
      typeArguments: typeArguments,
      defaults: defaults,
      type: owner,
      initializer: initializer,
      captures: captures,
      parameters: parameters.toList(),
      environment: environment,
      identity: declarationIdentity,
      identityArguments: identityArguments,
      storage: CallableStorage(
        type: owner,
        declarationIdentity: declarationIdentity,
        source: target,
        signature: signature,
        initializer: initializer,
        captures: captures,
        parameters: parameters,
        descriptors: environment,
      ),
    );
    _classes.add(
      IrClass(
        owner,
        fields,
        constructors: [?initializer],
        callableStorage: shape.storage,
      ),
    );
    return shape;
  }

  Iterable<ClosureShape> get all =>
      closures.values.followedBy(constants.values).followedBy(methods.values);

  ValueType _stored(ValueType type) => switch (valueCarrier(type)) {
    ValueType.integer => .integer,
    ValueType.boolean => .boolean,
    ValueType.floating => .floating,
    _ => .object.nullable,
  };

  FunctionTarget _initialize(
    ClassType owner,
    List<InstanceField> fields, {
    int? declarationIdentity,
    InstanceField? anchorField,
    bool selfAnchor = false,
    InstanceField? identityOrigin,
  }) {
    final target = FunctionTarget(
      null,
      'new',
      .voidType,
      fields.map((field) => field.type),
      owner: owner,
      kind: .initializer,
    );
    final entry = Block(target.parameterTypes);
    for (final (i, field) in fields.indexed) {
      entry.emit(
        StoreField(field, entry.parameters.first, entry.parameters[i + 1]),
      );
    }
    final receiver = entry.parameters.first;
    if (identityOrigin != null) {
      final original = entry.emit(
        CallableReference(entry.parameters[1 + fields.indexOf(identityOrigin)]),
      );
      if (!fields.contains(entryTable)) {
        entry.emit(
          StoreField(
            entryTable,
            receiver,
            entry.emit(LoadField(entryTable, original)),
          ),
        );
      }
      entry.emit(
        StoreField(
          environment,
          receiver,
          entry.emit(LoadField(environment, original)),
        ),
      );
      entry.emit(
        StoreField(
          identity,
          receiver,
          entry.emit(LoadField(identity, original)),
        ),
      );
      entry.emit(
        StoreField(
          identityAnchor,
          receiver,
          entry.emit(LoadField(identityAnchor, original)),
        ),
      );
    } else if (declarationIdentity != null) {
      entry.emit(StoreField(environment, receiver, receiver));
      entry.emit(
        StoreField(identity, receiver, Constant.integer(declarationIdentity)),
      );
      entry.emit(
        StoreField(
          identityAnchor,
          receiver,
          selfAnchor
              ? receiver
              : anchorField == null
              ? const Constant.nullValue()
              : entry.parameters[1 + fields.indexOf(anchorField)],
        ),
      );
      entry.emit(
        StoreField(identityArguments, receiver, const Constant.nullValue()),
      );
    }
    entry.finish(const Return());
    _functions.add(IrFunction(target, [entry]));
    return target;
  }
}

final class ClosureShape({
  required final CallableStorage storage,
  required final FunctionTarget target,
  required final FunctionTarget sourceTarget,
  required final FunctionType signature,
  required final List<ValueType> typeArguments,
  required final Map<int, Constant> defaults,
  required final ClassType type,
  required final FunctionTarget? initializer,
  final List<InstanceField> captures = const [],
  final List<TypeParameterType> parameters = const [],
  final List<InstanceField> environment = const [],

  /// The source declaration identity, independent of the selected call entry.
  required final int identity,

  /// Closed arguments retained even when absent from the function signature.
  final List<ValueType> identityArguments = const [],
});
