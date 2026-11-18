import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final branching in [false, true]) {
    test('typed storage result preserves actual helper paths ($branching)', () {
      final type = ClassType(null, 'Storage');
      final value = InstanceField(
        type,
        'value',
        .integer,
        initiallyUnbound: true,
      );
      final initializer = FunctionTarget(
        null,
        'initialize',
        .voidType,
        [.integer],
        owner: type,
        kind: .initializer,
      );
      final storage = CellStorage(
        type,
        value,
        null,
        initializer,
        ExecutionShape.word,
      );
      final cellType = CellType(ValueType.integer);
      final view = storage.viewOf(cellType);
      final init = Block(initializer.parameterTypes);
      init.emit(
        StoreField(
          value,
          init.parameters.first,
          init.parameters.last,
          storageView: view,
        ),
      );
      init.finish(const Return());
      final observed = FunctionTarget(null, 'observe', .voidType, [.integer]);
      final helper = FunctionTarget(null, 'createStorage', type, [.integer]);
      final body = Block(helper.parameterTypes);
      body.emit(DirectCall(observed, body.parameters));
      final helperBlocks = [body];
      if (branching) {
        final left = Block(), right = Block();
        body.finish(
          Branch(
            body.emit(
              Equals(body.parameters.single, const Constant.integer(42)),
            ),
            Jump(left),
            Jump(right),
          ),
        );
        for (final block in [left, right]) {
          block.finish(
            Return(
              block.emit(
                Construct(initializer, body.parameters, storageView: view),
              ),
            ),
          );
        }
        helperBlocks.addAll([left, right]);
      } else {
        body.finish(
          Return(
            body.emit(
              Construct(initializer, body.parameters, storageView: view),
            ),
          ),
        );
      }
      final implementation = IrFunction(helper, helperBlocks);
      final copyTarget = FunctionTarget(null, 'copyStorage', type, [type]);
      final copyBody = Block(copyTarget.parameterTypes);
      copyBody.finish(
        Return(
          copyBody.emit(
            Construct(initializer, [
              copyBody.emit(
                LoadField(value, copyBody.parameters.single, storageView: view),
              ),
            ], storageView: view),
          ),
        ),
      );
      final copyImplementation = IrFunction(copyTarget, [copyBody]);
      final root = FunctionTarget(null, 'root', .integer, [.integer]);
      final entry = Block(root.parameterTypes),
          done = Block([cellType]),
          copied = Block([cellType]),
          failed = Block();
      final allocation = NewCell(cellType, entry.parameters.single);
      entry.finish(
        Invoke(
          allocation,
          onReturn: Jump(done, [allocation]),
          onThrow: Jump(failed),
        ),
      );
      final copy = CopyCell(done.parameters.single);
      done.finish(
        Invoke(copy, onReturn: Jump(copied, [copy]), onThrow: Jump(failed)),
      );
      final read = copied.emit(ReadCell(copied.parameters.single));
      copied.finish(Return(read));
      failed.finish(const Return(Constant.integer(73)));
      final source = IrFunction(root, [entry, done, copied, failed]);
      final lowered = {
        allocation: (
          body: implementation,
          arguments: entry.parameters,
          environment: <TypeParameterType, ValueType>{},
          handler: Jump(failed),
        ),
        copy: (
          body: copyImplementation,
          arguments: <Value>[
            CellStorageReference(done.parameters.single, storage),
          ],
          environment: <TypeParameterType, ValueType>{},
          handler: Jump(failed),
        ),
      };
      final rewritten = FunctionRewrite(
        source,
        lowered: lowered,
        resultViews: {
          for (final operation in [allocation, copy])
            operation: (actual) => CellStorageView(actual, cellType, storage),
        },
        operations: {
          read: LoadField(
            value,
            CellStorageReference(copied.parameters.single, storage),
            storageView: view,
          ),
        },
      ).run();
      final calls = <Object?>[];
      final program = IrProgram(
        [
          IrClass(
            type,
            [value],
            constructors: [initializer],
            cellStorage: storage,
          ),
        ],
        [
          rewritten,
          IrFunction(initializer, [init]),
        ],
        externals: [IrExternal(observed)],
      );
      final runner = IrInterpreter(
        program,
        {},
        externalCalls: {
          observed: (args) {
            calls.add(args.single);
            if ((args.single as int) < 0) throw StateError('allocation failed');
            return null;
          },
        },
      );
      for (final n in [42, 7, -1]) {
        expect(runner.run(rewritten, [n]), n < 0 ? 73 : n);
        expect(calls, [n]);
        calls.clear();
      }
      expect(
        () => FunctionRewrite(
          source,
          lowered: lowered,
          resultViews: {
            allocation: (actual) => TypeView(actual, ValueType.object),
          },
        ).run(),
        throwsArgumentError,
      );
      expect(
        () => FunctionRewrite(
          source,
          resultViews: {
            allocation: (actual) => CellStorageView(actual, cellType, storage),
          },
        ).run(),
        throwsArgumentError,
      );
    });
  }
}
