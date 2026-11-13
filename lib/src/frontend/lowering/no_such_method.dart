import 'package:dartc/ir.dart';

import 'bindings.dart';

/// Lowers a typed forwarding body after ordinary argument entry checks.
IrFunction lowerNoSuchMethodForwarder(
  Bindings bindings,
  FunctionTarget target,
  FunctionTarget bodyTarget,
) {
  final entry = Block(target.parameterTypes);
  final arguments = entry.parameters.skip(target.argumentOffset).toList();
  final signature = target.signature;
  final selector = target.selector;
  final foreignPrivate =
      selector.privateScope != null && selector.privateScope != target.library;
  final invocation = entry.emit(
    MakeInvocation(
      foreignPrivate
          ? (
              kind: selector.kind,
              name: selector.name,
              privateScope: target.library,
            )
          : selector,
      arguments.take(signature.positionalCount),
      {
        for (final parameter in signature.named.entries)
          parameter.key: arguments[parameter.value.slot],
      },
      target.typeParameters,
    ),
  );
  if (foreignPrivate) {
    final construction = bodyTarget.resolveConstruction(bodyTarget.owner!);
    final arguments = bindings.bind(construction.target, (
      positional: [entry.parameters.first, invocation],
      named: const <String, Value>{},
    ));
    final error = entry.emit(
      construction.target.kind == .initializer
          ? Construct(
              construction.target,
              arguments,
              instantiatedType: construction.ownerType,
            )
          : DirectCall(
              construction.target,
              arguments,
              ownerType: construction.ownerType,
            ),
    );
    entry.finish(Throw(error));
  } else {
    Value result = entry.emit(
      InstanceCall(bodyTarget, entry.parameters.first, [invocation]),
    );
    if (!target.returnType.accepts(result.type)) {
      result = entry.emit(TypeCast(result, target.returnType));
    }
    entry.finish(
      target.returnType == ValueType.never
          ? Unreachable(result)
          : Return(result),
    );
  }
  return IrFunction(target, [entry], defaults: bindings.defaults(target));
}

/// A covariance wrapper binds its own defaults, then forwards every argument.
IrFunction lowerSuperForwarder(
  Bindings bindings,
  FunctionTarget target,
  FunctionTarget bodyTarget,
) {
  final entry = Block(target.parameterTypes);
  final arguments = entry.parameters.skip(target.argumentOffset).toList();
  final ordered = bindings.bind(bodyTarget, (
    positional: arguments.take(target.signature.positionalCount).toList(),
    named: {
      for (final parameter in target.signature.named.entries)
        parameter.key: arguments[parameter.value.slot],
    },
  ));
  final signature = bodyTarget
      .signatureFor(target.owner!)
      .instantiate(target.typeParameters);
  for (final (i, expected) in signature.parameters.indexed) {
    if (!expected.accepts(ordered[i].type)) {
      ordered[i] = entry.emit(TypeCast(ordered[i], expected));
    }
  }
  Value result = entry.emit(
    DirectCall(
      bodyTarget,
      [entry.parameters.first, ...ordered],
      ownerType: target.owner!.asInstanceOf(bodyTarget.owner!),
      typeArguments: target.typeParameters,
    ),
  );
  if (!target.returnType.accepts(result.type)) {
    result = entry.emit(TypeCast(result, target.returnType));
  }
  entry.finish(
    target.returnType == ValueType.never ? Unreachable(result) : Return(result),
  );
  return IrFunction(target, [entry], defaults: bindings.defaults(target));
}
