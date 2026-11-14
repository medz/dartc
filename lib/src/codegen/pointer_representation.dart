import 'package:dartc/ir.dart';

/// Keeps native addresses unboxed while preserving observable pointer identity.
final class PointerRepresentation._(
  List<IrFunction> functions,
  PointerRepresentation? outer,
) {
  new(Iterable<IrFunction> functions) : this._(functions.toList(), null);

  final _entries = {
    for (final function in functions)
      function.target: function.entry.parameters,
  };
  final _addresses = <Value>{};
  final _returns = <FunctionTarget>{};

  this {
    final candidates = <Object>{};
    final dependents = <Object, List<Object>>{};
    final escaped = <Object>[];
    final direct = <FunctionTarget>{};
    final observed = <FunctionTarget>{};
    for (final function in functions) {
      observed.addAll(
        function.functionConstants.map((v) => v.target.implementation),
      );
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation case DirectCall(:final target)) {
            direct.add(target.implementation);
          }
        }
      }
    }
    for (final function in functions) {
      final target = function.target;
      if (outer == null &&
          function.bodyKind == .synchronous &&
          target.kind == .function &&
          FfiTypes.isPointer(target.returnType) &&
          direct.contains(target) &&
          !observed.contains(target)) {
        candidates.add(target);
      }
      for (final block in function.blocks) {
        candidates.addAll([
          for (final (i, parameter) in block.parameters.indexed)
            if (FfiTypes.isPointer(parameter.type) &&
                function.bodyKind == .synchronous &&
                (block != function.entry ||
                    outer == null ||
                    outer.contains(target, i)))
              parameter,
        ]);
        candidates.addAll(
          [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ].where(
            (v) =>
                v is PointerFromAddress ||
                v is PointerOffset ||
                v is NativeCall && FfiTypes.isPointer(v.type) ||
                v is TypeView &&
                    FfiTypes.isPointer(v.type) &&
                    FfiTypes.isPointer(v.operand.type),
          ),
        );
      }
    }
    void requires(Object value, Object condition) {
      (dependents[condition] ??= []).add(value);
      if (!candidates.contains(condition)) escaped.add(value);
    }

    for (final function in functions) {
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation case DirectCall(:final target)
              when FfiTypes.isPointer(operation.type)) {
            final result = target.implementation;
            if (candidates.contains(result) ||
                outer?.returnsAddress(result) == true) {
              candidates.add(operation);
              if (candidates.contains(result)) {
                requires(operation, result);
                requires(result, operation);
              }
            }
          }
        }
      }
    }
    for (final function in functions) {
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          for (final (i, input) in operation.inputs.indexed) {
            if (!candidates.contains(input)) continue;
            if (operation is PointerAddress ||
                operation is PointerOffset ||
                operation is NativeCall ||
                operation is KeepAlive ||
                operation is ObjectHashCode && !operation.direct ||
                operation is Equals &&
                    FfiTypes.isPointer(operation.left.type) &&
                    FfiTypes.isPointer(operation.right.type)) {
              continue;
            }
            if (operation is TypeView && candidates.contains(operation)) {
              requires(input, operation);
              continue;
            }
            if (operation case DirectCall(:final target)) {
              final parameters = _entries[target.implementation];
              if (parameters != null) {
                requires(input, parameters[i]);
                continue;
              }
              if (outer?.contains(target, i) == true) continue;
            }
            escaped.add(input);
          }
        }
        switch (block.end) {
          case Return(value: final value?):
            requires(value, function.target);
          case Throw(exception: final value) ||
              Yield(:final value) ||
              Await(operand: final value):
            escaped.add(value);
          default:
            break;
        }
        for (final edge in block.successors) {
          for (final (i, value) in edge.arguments.indexed) {
            requires(value, edge.target.parameters[i]);
          }
        }
      }
    }
    while (escaped.isNotEmpty) {
      final value = escaped.removeLast();
      if (candidates.remove(value)) {
        escaped.addAll(dependents[value] ?? const []);
      }
    }
    _addresses.addAll(candidates.whereType<Value>());
    _returns.addAll(candidates.whereType<FunctionTarget>());
  }

  /// Whether the selected entry receives parameter [index] as an address.
  bool contains(FunctionTarget target, int index) =>
      _addresses.contains(_entries[target.implementation]?[index]);

  /// Whether all uses of this return value permit an address result.
  bool returnsAddress(FunctionTarget target) =>
      _returns.contains(target.implementation);

  /// Generated bodies use the same rules with already fixed source signatures.
  Set<Value> addressesIn(IrFunction function) =>
      _entries.containsKey(function.target)
      ? _addresses
      : PointerRepresentation._([function], this)._addresses;
}
