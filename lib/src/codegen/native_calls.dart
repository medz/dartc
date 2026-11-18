import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

/// Native function-pointer adapters whose internal inputs are scalar values.
final class NativeCalls() {
  final entries =
      <FunctionTarget, ({NativeSignature signature, bool isLeaf})>{};
  final _targets =
      <({NativeSignature signature, bool isLeaf}), FunctionTarget>{};

  FunctionTarget target(NativeSignature signature, {required bool isLeaf}) =>
      _targets.putIfAbsent((signature: signature, isLeaf: isLeaf), () {
        final target = FunctionTarget(
          null,
          'nativeCall',
          FfiTypes.rawValueType(signature.result),
          [
            ValueType.integer,
            if (signature.result is NativeCompoundType) ValueType.integer,
            ...signature.parameters.map(FfiTypes.rawValueType),
          ],
        );
        entries[target] = (signature: signature, isLeaf: isLeaf);
        return target;
      });
}
