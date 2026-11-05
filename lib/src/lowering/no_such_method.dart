import 'package:dartc/ir.dart';

import 'bindings.dart';

/// A typed forwarder is an ordinary body: entry binding/checks have already
/// happened, and only the invocation of this.noSuchMethod is dynamic.
IrFunction lowerNoSuchMethodForwarder(
  Bindings bindings,
  FunctionTarget target,
) {
  final entry = Block(target.parameterTypes);
  final arguments = entry.parameters.skip(target.argumentOffset).toList();
  final signature = target.signature;
  final invocation = entry.emit(
    MakeInvocation(target.selector, arguments.take(signature.positionalCount), {
      for (final parameter in signature.named.entries)
        parameter.key: arguments[parameter.value.slot],
    }, target.typeParameters),
  );
  Value result = entry.emit(
    DynamicDispatch(
      entry.parameters.first,
      (kind: FunctionKind.method, name: 'noSuchMethod', privateLibrary: null),
      [invocation],
    ),
  );
  if (target.returnType != ValueType.voidType) {
    result = entry.emit(TypeCast(result, target.returnType));
  }
  entry.finish(
    target.returnType == ValueType.never ? Unreachable(result) : Return(result),
  );
  return IrFunction(target, [entry], defaults: bindings.defaults(target));
}
