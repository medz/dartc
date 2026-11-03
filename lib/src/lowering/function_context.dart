import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// The instructions and local SSA values at the current point in a function.
final class FunctionContext {
  final ResolvedUnitResult unit;
  final TargetBindings bindings;
  final blocks = <Block>[];
  final locals = <VariableElement, Value>{};
  Block? current;

  FunctionContext(this.unit, this.bindings);

  Block addBlock([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    blocks.add(block);
    return block;
  }
}
