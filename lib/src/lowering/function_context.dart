import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// The open control-flow graph and local bindings for one function.
final class FunctionContext(
  /// The source unit used for resolved identities and diagnostic locations.
  final ResolvedUnitResult unit,

  /// The call targets shared by all functions in this batch.
  final TargetBindings bindings,
) {
  /// The blocks created so far, with the function entry first.
  final blocks = <Block>[];

  /// The SSA value of each in-scope variable on the current path.
  final locals = <VariableElement, Value>{};

  /// The block receiving instructions, or `null` after a terminating transfer.
  Block? current;

  /// Appends an open block with parameters of [types] and returns it.
  Block addBlock([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    blocks.add(block);
    return block;
  }
}
