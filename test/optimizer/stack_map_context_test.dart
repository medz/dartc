import 'dart:ffi' show Int64;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a later lowering restores the table comparison from the original graph',
    () {
      final context = ClassType(null, 'Continuation');
      final waiting = ClassType(null, 'Waiting', interfaces: [context]);
      final source = FunctionTarget(
        null,
        'run',
        .integer,
        [],
        owner: waiting,
        kind: .method,
      );
      final frame = FunctionTarget(
        null,
        'frame',
        .integer,
        source.parameterTypes,
        executionSource: source,
      );
      final inspect = FunctionTarget(null, 'inspect', .integer, []);
      final generated = Block(frame.parameterTypes);
      generated.finish(Return(generated.emit(DirectCall(inspect, []))));
      final table = FunctionTarget(null, 'table', .integer, []);
      final tableBody = Block();
      tableBody.emit(DirectCall(inspect, []));
      tableBody.finish(Return(tableBody.emit(StackMapAddress())));
      final read = FunctionTarget(null, 'read', .integer, []);
      final reader = Block();
      final address = reader.emit(DirectCall(table, []));
      final query = reader.emit(StackMapAddress(contextFreeOnly: true));
      final yes = Block()..finish(const Return(Constant.integer(1)));
      final no = Block()..finish(const Return(Constant.integer(0)));
      reader.finish(
        Branch(reader.emit(Equals(address, query)), Jump(yes), Jump(no)),
      );
      final failed = FunctionTarget(null, 'fail', .never, []);
      final graph = IrProgram(
        [IrClass(context, []), IrClass(waiting, [])],
        [
          IrFunction(read, [reader, yes, no]),
          IrFunction(table, [tableBody]),
        ],
        externals: [IrExternal(failed), IrExternal(inspect)],
        nativeBoundaries: NativeBoundaryBindings(
          exports: {read: (entry: read, signature: NativeSignature(Int64, []))},
          failure: failed,
          context: NativeData(
            List.filled(RuntimeContext.size, 0),
            alignment: 8,
            contextOwner: NativeContextOwner(null, failed),
          ),
        ),
      );
      final introduce = _AddFrame(table, IrFunction(frame, [generated]), read);
      final facts = ProgramOptimizer([const ProgramSimplification(), introduce])
          .run(graph, [], openEntries: [read], stackContext: context);
      expect(introduce.sawFoldedRead, isTrue);
      expect(facts.definitions, contains(frame));
      expect(facts.returnedBy(read).integers?.constant, isNull);
    },
  );

  for (final route in ['producer', 'native reentry', 'inherited frame']) {
    test('a later $route wakes a reader of the linked stack table', () {
      final context = ClassType(null, 'Continuation');
      final receiver = ClassType(null, 'Waiting', interfaces: [context]);
      final method = FunctionTarget(
        null,
        'run',
        .integer,
        [],
        owner: receiver,
        kind: .method,
      );
      final inspect = FunctionTarget(null, 'inspect', .integer, []);
      final methodBody = Block(method.parameterTypes);
      methodBody.finish(Return(methodBody.emit(DirectCall(inspect, []))));

      final entry = FunctionTarget(null, 'read', .integer, [.integer]);
      final read = Block(entry.parameterTypes);
      final maps = read.emit(StackMapAddress());
      final query = read.emit(StackMapAddress(contextFreeOnly: true));
      final flags = read.emit(Equals(maps, query));
      final absent = read.emit(Equals(query, const Constant.integer(0)));
      final foreign = read.emit(Equals(read.parameters.single, query));
      read.finish(Return(query));
      final opaque = FunctionTarget(null, 'opaque', .voidType, [.integer]);
      final callback = StaticCallbackTarget(
        inspect,
        FunctionType(FfiTypes.int64, []),
        exceptionalReturn: const Constant.integer(-1),
      );
      final next = FunctionTarget(null, 'next', .integer, []);
      final nextBody = Block();
      if (route == 'producer') {
        nextBody.emit(DirectCall(method, [ObjectConstant(receiver, const {})]));
      } else if (route == 'native reentry') {
        final address = nextBody.emit(NativeCallbackAddress(callback));
        nextBody.emit(DirectCall(opaque, [address]));
      }
      nextBody.finish(const Return(Constant.integer(19)));
      final failed = FunctionTarget(null, 'fail', .never, []);
      final raw = NativeSignature(Int64, []);
      final graph = IrProgram(
        [
          IrClass(context, []),
          IrClass(receiver, [], members: [method]),
        ],
        [
          IrFunction(entry, [read]),
          IrFunction(next, [nextBody]),
          IrFunction(method, [methodBody]),
          IrFunction(inspect, [
            Block()..finish(const Return(Constant.integer(3))),
          ]),
        ],
        externals: [IrExternal(failed), IrExternal(opaque)],
        nativeBoundaries: NativeBoundaryBindings(
          exports: {
            entry: (entry: entry, signature: NativeSignature(Int64, [Int64])),
            if (route != 'inherited frame') next: (entry: next, signature: raw),
          },
          failure: failed,
          context: NativeData(
            List.filled(RuntimeContext.size, 0),
            alignment: 8,
            contextOwner: NativeContextOwner(null, failed),
          ),
        ),
      );
      final flow = ProgramFlow(
        graph,
        [],
        openEntries: [entry],
        stackContext: context,
      );
      expect((flow.facts.valueOf(flags).constant as ScalarConstant).value, isTrue);
      expect(
        (flow.facts.valueOf(absent).constant as ScalarConstant).value,
        isFalse,
      );
      expect(flow.facts.valueOf(foreign).constant, isNull);
      expect(
        () => flow.facts.checkStackMapContexts(context, hasContexts: true),
        throwsStateError,
      );
      expect(
        () => flow.facts.checkStackMapContexts(receiver, hasContexts: false),
        throwsArgumentError,
      );
      expect(flow.facts.definitions, isNot(contains(method)));
      expect(flow.extend(openEntries: [next]), isTrue);
      expect(flow.facts.valueOf(flags).constant, isNull);
      expect(flow.facts.valueOf(absent).constant, isNull);
      expect(
        flow.facts.valueOf(query).addresses,
        flow.facts.valueOf(maps).addresses,
      );
      expect(
        flow.facts.valueOf(query).constants.whereType<ScalarConstant>().map((c) => c.value),
        contains(0),
      );
      if (route == 'producer') expect(flow.facts.definitions, contains(method));
      if (route == 'native reentry') {
        expect(flow.facts.definitions, contains(inspect));
      }
      flow.facts.checkStackMapContexts(context, hasContexts: true);
    });
  }
}

/// Adds a generated method after an earlier reduction can fold the header.
final class _AddFrame(
  final FunctionTarget table,
  final IrFunction frame,
  final FunctionTarget read,
) extends ProgramPass {
  bool sawFoldedRead = false;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    final input = facts.program;
    if (input.implementationOf(frame.target) != null) return input;
    final reader = input.implementationOf(read) as IrFunction;
    sawFoldedRead |=
        reader.blocks.every((b) => b.end is! Branch) &&
        reader.blocks.any(
          (b) => b.end is Return && (b.end as Return).value is Constant,
        );
    final body = Block();
    body.emit(
      DirectCall(frame.target, [
        ObjectConstant(frame.target.parameterTypes.single as ClassType, {}),
      ]),
    );
    body.finish(Return(body.emit(StackMapAddress())));
    return IrProgram(
      input.classes,
      [
        for (final f in input.functions)
          f.target == table ? IrFunction(table, [body]) : f,
        frame,
      ],
      externals: input.externals,
      nativeBoundaries: input.nativeBoundaries,
    );
  }
}
