import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

/// Native function-pointer adapters whose internal inputs are scalar values.
final class NativeCalls() {
  final signatures = <FunctionTarget, NativeSignature>{};
  final _targets = <NativeSignature, FunctionTarget>{};

  FunctionTarget target(NativeSignature signature) => _targets.putIfAbsent(
    signature,
    () {
      ValueType raw(NativeTypeRef type) =>
          type.isFloating ? .floating : .integer;
      final target = FunctionTarget(null, 'nativeCall', raw(signature.result), [
        ValueType.integer,
        if (signature.result is NativeCompoundType) ValueType.integer,
        ...signature.parameters.map(raw),
      ]);
      signatures[target] = signature;
      return target;
    },
  );
}
