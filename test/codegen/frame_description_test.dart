import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/frame_description.dart';
import 'package:test/test.dart';

import '../../sdk/runtime/stack_trace.dart';
import '../support/ir_interpreter.dart';

void main() {
  test(
    'nested inlining preserves throw and rethrow frame identities and sites',
    () {
      final uri = Uri.parse('memory:inline-frames');
      final failure = FunctionTarget(uri, 'fail', .integer, [.integer]);
      final leaf = FunctionTarget(uri, 'leaf', .integer, []);
      final middle = FunctionTarget(uri, 'middle', .integer, []);
      final root = FunctionTarget(uri, 'root', .integer, []);
      SourceLocation at(String file, int line, int column) => SourceLocation((
        uri: Uri.parse('file:///$file.dart'),
        line: line,
        column: column,
      ));
      final leafSite = at('leaf_part', 3, 4);
      final middleSite = at('middle', 5, 6);
      final rootSite = at('root', 7, 8);
      final rethrowSite = at('root', 9, 10);
      IrFunction forward(
        FunctionTarget target,
        FunctionTarget callee,
        SourceLocation site,
      ) {
        final entry = Block();
        final call = entry.emit(
          DirectCall(callee, [
            if (callee == failure) const Constant.integer(0),
          ]),
        );
        entry.finish(Return(call));
        return IrFunction(target, [entry], sourceLocations: {call: site});
      }

      final entry = Block(), normal = Block([ValueType.integer]);
      final caught = Block([ValueType.object, ValueType.stackTrace]);
      final call = DirectCall(middle, []);
      entry.finish(
        Invoke(
          call,
          onReturn: Jump(normal, [call]),
          onThrow: Jump(caught, [
            UnwindValue.exception,
            UnwindValue.stackTrace,
          ]),
        ),
      );
      normal.finish(Return(normal.parameters.single));
      caught.finish(
        Throw(caught.parameters[0], stackTrace: caught.parameters[1]),
      );
      final source = IrProgram(
        [],
        [
          forward(leaf, failure, leafSite),
          forward(middle, leaf, middleSite),
          IrFunction(
            root,
            [entry, normal, caught],
            sourceLocations: {call: rootSite, caught: rethrowSite},
          ),
        ],
        externals: [IrExternal(failure)],
      );
      IrProgram inline(IrProgram program) =>
          inlineDirectCalls(program, CallTypeFlow(program, [root]).facts);
      final preparedCallee = inlineDirectCalls(
        source,
        CallTypeFlow(source, [middle]).facts,
      );
      for (final result in [inline(inline(source)), inline(preparedCallee)]) {
        expect(CallTypeFlow(result, [root]).facts.definitions, {root, failure});
        final rewritten = result.implementationOf(root) as IrFunction;
        final invocation = rewritten.blocks
            .map((b) => b.end)
            .whereType<Invoke>()
            .single;
        final origin = rewritten.sourceLocations[invocation.operation]!;
        expect(origin.function, same(leaf));
        expect(origin.caller!.function, same(middle));
        expect(origin.caller!.caller!.function, isNull);
        expect(origin.caller!.caller!.caller, isNull);
        final description = frameDescription(root, origin);
        expect(
          description,
          'leaf (file:///leaf_part.dart:3:4)\n'
          'middle (file:///middle.dart:5:6)\nroot (file:///root.dart:7:8)',
        );
        final rethrowBlock = rewritten.blocks.singleWhere(
          (b) => b.end is Throw,
        );
        final rethrowEnd = rethrowBlock.end as Throw;
        expect(rethrowEnd.exception, same(rethrowBlock.parameters[0]));
        expect(rethrowEnd.stackTrace, same(rethrowBlock.parameters[1]));
        expect(
          frameDescription(root, rewritten.sourceLocations[rethrowBlock]),
          'root (file:///root.dart:9:10)',
        );
        final before = CapturedStackTrace(
          3,
          CapturedStackTrace(
            2,
            CapturedStackTrace(1, null, frameDescription(leaf, leafSite)),
            frameDescription(middle, middleSite),
          ),
          frameDescription(root, rootSite),
        );
        final after = CapturedStackTrace(3, null, description);
        expect(after.toString(), before.toString());
        final error = StateError('original');
        for (final (program, trace) in [(source, before), (result, after)]) {
          final interpreter = IrInterpreter(program, {
            (uri, 'fail'): (_) => Error.throwWithStackTrace(error, trace),
          });
          try {
            interpreter.run(program.implementationOf(root) as IrFunction, []);
            fail('The throw must propagate through the rethrow.');
          } catch (caught, stack) {
            expect(caught, same(error));
            expect(stack.toString(), before.toString());
          }
        }
      }
      expect(source.functions.last.sourceLocations[call], same(rootSite));
    },
  );

  test(
    'missing positions preserve logical names and hide generated frames',
    () {
      final uri = Uri.parse('memory:frames');
      final owner = ClassType.declare(uri, 'Worker');
      final method = FunctionTarget(
        uri,
        'work',
        .voidType,
        [],
        kind: .method,
        owner: owner,
      );
      final local = FunctionTarget(
        uri,
        'local',
        .voidType,
        [],
        kind: .closure,
        enclosing: method,
        sourceOffset: 1,
      );
      final generated = FunctionTarget(null, 'generated', .voidType, []);
      final origin = SourceLocation(
        null,
        function: local,
        caller: SourceLocation(null),
      );
      expect(frameDescription(generated, origin), 'Worker.work.local');
      expect(frameDescription(generated), isNull);
      expect(frameDescription(method), 'Worker.work');
      final callSite = SourceLocation((uri: uri, line: 2, column: 3));
      expect(
        frameDescription(
          method,
          SourceLocation(null).inlinedAt(local, callSite),
        ),
        'Worker.work.local\nWorker.work (memory:frames:2:3)',
      );
    },
  );
}
