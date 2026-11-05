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
      selector.privateLibrary != null &&
      selector.privateLibrary != target.library;
  final invocation = entry.emit(
    MakeInvocation(
      foreignPrivate
          ? (
              kind: selector.kind,
              name: selector.name,
              privateLibrary: target.library,
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
    final error = entry.emit(
      DirectCall(bodyTarget, [entry.parameters.first, invocation]),
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
  final ordered = List<Value>.of(arguments);
  for (final parameter in bodyTarget.signature.named.entries) {
    ordered[parameter.value.slot] =
        arguments[target.signature.named[parameter.key]!.slot];
  }
  final result = entry.emit(
    DirectCall(
      bodyTarget,
      [entry.parameters.first, ...ordered],
      ownerType: target.owner!.asInstanceOf(bodyTarget.owner!),
      typeArguments: target.typeParameters,
    ),
  );
  entry.finish(
    target.returnType == ValueType.never ? Unreachable(result) : Return(result),
  );
  return IrFunction(target, [entry], defaults: bindings.defaults(target));
}
