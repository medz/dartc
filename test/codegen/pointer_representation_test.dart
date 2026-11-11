import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/frame_lookup.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/pointer_parameters.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:pointer-representation');
  final pointerType = FfiTypes.int64Pointer;

  test('direct call chains agree on unboxed pointer parameters', () {
    final read = FunctionTarget(uri, 'read', .integer, [pointerType]);
    final forward = FunctionTarget(uri, 'forward', .integer, [pointerType]);
    final caller = FunctionTarget(uri, 'caller', .integer, []);
    final a = Block(read.parameterTypes);
    a.finish(Return(a.emit(PointerAddress(a.parameters.single))));
    final b = Block(forward.parameterTypes);
    b.finish(Return(b.emit(DirectCall(read, b.parameters))));
    final c = Block();
    final pointer = c.emit(
      PointerFromAddress(const Constant.integer(32), pointerType),
    );
    c.finish(Return(c.emit(DirectCall(forward, [pointer]))));
    final program = IrProgram([], [
      IrFunction(read, [a]),
      IrFunction(forward, [b]),
      IrFunction(caller, [c]),
    ]);
    final layouts = ProgramLayout([], functions: program.functions);
    final members = MemberCalls(program, {read, forward, caller});
    for (final function in program.functions) {
      final body = FunctionRepresentation(
        function,
        layouts,
        CheckedCasts(),
        members,
        HeapPlan(FrameLookup()),
      );
      for (final parameter in function.entry.parameters) {
        expect(parameter.type, pointerType);
        expect(body.typeOf(parameter), ValueType.integer);
      }
      expect(body.boxes, isEmpty);
      expect(body.invocations.keys.whereType<PointerFromAddress>(), isEmpty);
    }
    expect(layouts.entryTypes(forward), [ValueType.integer]);
  });

  test('identity observation propagates through recursive call cycles', () {
    for (final observe in [false, true]) {
      final a = FunctionTarget(uri, 'a', .integer, [pointerType]);
      final b = FunctionTarget(uri, 'b', .integer, [pointerType]);
      final x = Block(a.parameterTypes), y = Block(b.parameterTypes);
      x.finish(Return(x.emit(DirectCall(b, x.parameters))));
      if (observe) {
        y.emit(Identical(y.parameters.single, y.parameters.single));
      }
      y.finish(Return(y.emit(DirectCall(a, y.parameters))));
      final parameters = PointerParameters([
        IrFunction(a, [x]),
        IrFunction(b, [y]),
      ]);
      expect(parameters.contains(a, 0), !observe);
      expect(parameters.contains(b, 0), !observe);
    }
  });

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
