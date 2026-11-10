import 'package:dartc/ir.dart';

/// The mutable control-flow graph consumed by native instruction selection.
abstract class SelectedGraph() {
  final blocks = <Block>[];
  final instructions = <Block, List<Value>>{};
  final ends = <Block, Terminator>{};

  Block addBlock([List<ValueType> parameters = const []]) {
    final block = Block(parameters);
    blocks.add(block);
    instructions[block] = [];
    return block;
  }
}
