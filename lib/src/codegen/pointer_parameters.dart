import 'package:dartc/ir.dart';

/// Proves which pointer parameters are consumed only as native addresses.
final class PointerParameters(Iterable<IrFunction> functions) {
  final _entries = {
    for (final function in functions)
      function.target: function.entry.parameters,
  };
  final _addresses = <Value>{};

  this {
    for (final parameters in _entries.values) {
      _addresses.addAll(parameters.where((p) => FfiTypes.isPointer(p.type)));
    }
    final dependents = <Value, List<Value>>{};
    final escaped = <Value>[];
    for (final function in functions) {
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          for (final (i, input) in operation.inputs.indexed) {
            if (!_addresses.contains(input)) continue;
            if (operation is PointerAddress || operation is PointerOffset) {
              continue;
            }
            if (operation case DirectCall(:final target)
                when _entries.containsKey(target.implementation)) {
              final parameter = _entries[target.implementation]![i];
              (dependents[parameter] ??= []).add(input);
              if (_addresses.contains(parameter)) continue;
            }
            escaped.add(input);
          }
        }
        switch (block.end) {
          case Return(value: final value?) ||
              Throw(exception: final value) ||
              Yield(:final value) ||
              Await(operand: final value):
            escaped.add(value);
          default:
            break;
        }
        for (final edge in block.successors) {
          escaped.addAll(edge.arguments);
        }
      }
    }
    while (escaped.isNotEmpty) {
      final value = escaped.removeLast();
      if (_addresses.remove(value)) {
        escaped.addAll(dependents[value] ?? const []);
      }
    }
  }

  /// Whether the selected entry receives parameter [index] as an address.
  bool contains(FunctionTarget target, int index) =>
      _addresses.contains(_entries[target.implementation]?[index]);

  /// Whether an operand's identity is unobservable at this use.
  bool accepts(Instruction operation, int index) =>
      operation is PointerAddress ||
      operation is PointerOffset ||
      operation is DirectCall && contains(operation.target, index);
}
