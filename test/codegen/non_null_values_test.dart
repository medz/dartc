import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/non_null_values.dart';
import 'package:test/test.dart';

void main() {
  test('loop backedges preserve proof only when every incoming edge does', () {
    for (final nullable in [false, true]) {
      final target = FunctionTarget(
        Uri.parse('memory:null-flow'),
        'loop',
        .object.nullable,
        [.object, .boolean],
      );
      final entry = Block(target.parameterTypes),
          loop = Block([.object.nullable]),
          body = Block(),
          done = Block();
      entry.finish(Jump(loop, [entry.parameters.first]));
      loop.finish(Branch(entry.parameters.last, Jump(body), Jump(done)));
      body.finish(
        Jump(loop, [
          nullable ? const Constant.nullValue() : loop.parameters.single,
        ]),
      );
      done.finish(Return(loop.parameters.single));
      final facts = NonNullValues(
        IrFunction(target, [entry, loop, body, done]),
      );
      expect(facts.contains(loop.parameters.single), !nullable);
    }
  });
}
