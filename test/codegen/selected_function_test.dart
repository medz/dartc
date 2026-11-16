import 'dart:ffi' as ffi;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/native_invocation.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:test/test.dart';

void main() {
  final layouts = ProgramLayout(
    [],
    nativeLayout: NativeLayout(const Target(.linux, .arm64)),
  );
  final location = SourceLocation((
    uri: Uri.parse('memory:pruning'),
    line: 1,
    column: 1,
  ));

  test('pruning removes dead metadata and keeps live origins and operands', () {
    final target = FunctionTarget(null, 'pruned', .integer, [.integer]);
    final entry = Block(target.parameterTypes),
        live = Block([.integer]),
        dead = Block();
    final body = SelectedFunction(target, layouts, entry);
    body.blocks.addAll([entry, live, dead]);
    final value = IntBinary(
      .add,
      entry.parameters.single,
      const Constant.integer(1),
    );
    final deadValue = IntBinary(
      .add,
      const Constant.integer(2),
      const Constant.integer(3),
    );
    final deadTest = TypeTest(const Constant.integer(1), .string);
    final liveJump = Jump(live, [value]), deadJump = Jump(dead);
    final liveEnd = Return(live.parameters.single);
    body.instructions[entry] = [value];
    body.instructions[live] = [];
    body.instructions[dead] = [deadValue, deadTest];
    body.ends[entry] = Branch(const Constant.boolean(true), liveJump, deadJump);
    body.ends[live] = liveEnd;
    body.ends[dead] = Return(const Constant.integer(0));
    body.edgeArguments[liveJump] = [value];
    body.edgeArguments[deadJump] = const [];
    body.operands[value] = [value.left, value.right];
    body.operands[deadValue] = [deadValue.left, deadValue.right];
    body.resultTypes[value] = .integer;
    body.resultTypes[deadValue] = .integer;
    body.tests[deadTest] = TypeTestKind.constantFalse;
    body.aliases.add(deadValue);
    body.introduced.add(deadValue);
    body.callOrigins[deadValue] = deadValue;
    for (final site in [
      entry,
      live,
      value,
      liveEnd,
      dead,
      deadValue,
      deadTest,
    ]) {
      body.sourceLocations[site] = location;
    }

    body.prune();

    expect(body.blocks, [entry, live]);
    expect(body.edgeArguments, {
      liveJump: [value],
    });
    expect(body.inputsOf(value), [value.left, value.right]);
    expect(body.operands.containsKey(deadValue), isFalse);
    expect(body.resultTypes, {value: ValueType.integer});
    expect(body.tests, isEmpty);
    expect(body.aliases, isEmpty);
    expect(body.introduced, isEmpty);
    expect(body.callOrigins, isEmpty);
    expect(body.sourceLocations, {
      entry: location,
      live: location,
      value: location,
      liveEnd: location,
    });
  });

  test('pruning retains call metadata for a live invoke terminator', () {
    final target = FunctionTarget(null, 'pruned', .integer, []);
    final entry = Block(), failure = Block(), exit = Block();
    final body = SelectedFunction(target, layouts, entry);
    body.blocks.addAll([entry, failure, exit]);
    final callee = FunctionTarget(null, 'callee', .voidType, [.integer]);
    final argument = const Constant.integer(42);
    final invoke = DirectCall(callee, [argument]);
    for (final block in body.blocks) {
      body.instructions[block] = [];
    }
    body.ends[entry] = Invoke(
      invoke,
      onReturn: Jump(exit),
      onThrow: Jump(failure),
    );
    body.ends[failure] = Return(const Constant.integer(0));
    body.ends[exit] = Return(const Constant.integer(1));
    body.operands[invoke] = [argument];
    body.invocations[invoke] = callee;
    body.resultTypes[invoke] = .voidType;
    body.sourceLocations[invoke] = location;

    body.prune();

    expect(body.invocations[invoke], callee);
    expect(body.inputsOf(invoke), [argument]);
    expect(body.operands[invoke], [argument]);
    expect(body.resultTypes[invoke], ValueType.voidType);
    expect(body.sourceLocations[invoke], location);
  });

  test(
    'pruning preserves native call origins and only live parameter types',
    () {
      final target = FunctionTarget(null, 'native', .voidType, [.integer]);
      final entry = Block(target.parameterTypes), dead = Block([.integer]);
      final body = SelectedFunction(target, layouts, entry);
      final call = NativeInvocation(
        entry.parameters.single,
        [],
        NativeSignature(ffi.Void, []),
        isLeaf: false,
      );
      body.blocks.addAll([entry, dead]);
      body.instructions[entry] = [call];
      body.instructions[dead] = [];
      body.ends[entry] = const Return();
      body.ends[dead] = const Return();
      body.sourceLocations[call] = location;
      body.operands[call] = [entry.parameters.single];
      body.resultTypes[entry.parameters.single] = .integer;
      body.resultTypes[dead.parameters.single] = .integer;

      body.prune();

      expect(body.sourceLocations[call], location);
      expect(body.operands[call], [entry.parameters.single]);
      expect(body.resultTypes, {entry.parameters.single: ValueType.integer});
    },
  );
}
