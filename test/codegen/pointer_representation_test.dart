import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/frame_lookup.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:pointer-representation');
  final pointerType = FfiTypes.int64Pointer;

  FunctionRepresentation select(
    ValueType result,
    List<Block> blocks, {
    Iterable<IrExternal> externals = const [],
  }) {
    final target = FunctionTarget(uri, 'test', result, []);
    final function = IrFunction(target, blocks);
    final program = IrProgram([], [function], externals: externals);
    return FunctionRepresentation(
      function,
      ProgramLayout([]),
      CheckedCasts(),
      MemberCalls(program, {target}),
      HeapPlan(FrameLookup()),
    );
  }

  test('local address chains neither allocate nor become managed roots', () {
    final entry = Block();
    final pointer = entry.emit(
      PointerFromAddress(const Constant.integer(32), pointerType),
    );
    final offset = entry.emit(
      PointerOffset(pointer, const Constant.integer(-2)),
    );
    entry.finish(Return(entry.emit(PointerAddress(offset))));
    final body = select(.integer, [entry]);
    expect(body.invocations, isEmpty);
    for (final value in [pointer, offset]) {
      expect(body.aliases, contains(value));
      expect(body.layouts.isReference(body.typeOf(value)), isFalse);
    }
  });

  test('observing the offset identity does not materialize its base', () {
    final entry = Block();
    final pointer = entry.emit(
      PointerFromAddress(const Constant.integer(32), pointerType),
    );
    final offset = entry.emit(
      PointerOffset(pointer, const Constant.integer(0)),
    );
    entry.finish(Return(offset));
    final body = select(pointerType, [entry]);
    expect(body.aliases, contains(pointer));
    expect(body.invocations.keys, [offset]);
    expect(body.layouts.isReference(body.typeOf(offset)), isTrue);
  });

  for (final use in ['return', 'throw', 'edge', 'identity', 'call']) {
    test('$use retains pointer identity and traced storage', () {
      final entry = Block();
      final pointer = entry.emit(
        PointerFromAddress(const Constant.integer(0), pointerType),
      );
      final blocks = [entry];
      final externals = <IrExternal>[];
      ValueType result = pointerType;
      switch (use) {
        case 'return':
          entry.finish(Return(pointer));
        case 'throw':
          entry.finish(Throw(pointer));
        case 'edge':
          final done = Block([pointerType]);
          entry.finish(Jump(done, [pointer]));
          done.finish(Return(done.parameters.single));
          blocks.add(done);
        case 'identity':
          result = .boolean;
          entry.finish(Return(entry.emit(Identical(pointer, pointer))));
        case 'call':
          final receiver = FunctionTarget(uri, 'consume', pointerType, [
            pointerType,
          ]);
          externals.add(IrExternal(receiver));
          entry.emit(DirectCall(receiver, [pointer]));
          result = .integer;
          entry.finish(Return(entry.emit(PointerAddress(pointer))));
      }
      final body = select(result, blocks, externals: externals);
      expect(body.invocations, contains(pointer));
      expect(body.layouts.isReference(body.typeOf(pointer)), isTrue);
    });
  }
}
