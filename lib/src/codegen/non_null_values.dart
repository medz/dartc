import 'package:dartc/ir.dart';

/// Proves non-null block arguments across joins and loop backedges.
final class NonNullValues(final IrFunction function) {
  final _parameters = <BlockParameter>{};

  this {
    final incoming = <BlockParameter, List<Value>>{};
    for (final block in function.blocks.skip(1)) {
      for (final parameter in block.parameters) {
        incoming[parameter] = [];
        _parameters.add(parameter);
      }
    }
    for (final block in function.blocks) {
      for (final edge in block.successors) {
        for (final (i, value) in edge.arguments.indexed) {
          incoming[edge.target.parameters[i]]?.add(value);
        }
      }
    }
    bool changed;
    do {
      changed = false;
      for (final MapEntry(key: parameter, value: values) in incoming.entries) {
        if (_parameters.contains(parameter) &&
            (values.isEmpty || !values.every(contains))) {
          _parameters.remove(parameter);
          changed = true;
        }
      }
    } while (changed);
  }

  bool contains(Value value) =>
      !value.type.mayBeNull ||
      switch (value) {
        TypeView(:final operand) => contains(operand),
        BlockParameter() => _parameters.contains(value),
        _ => false,
      };
}
