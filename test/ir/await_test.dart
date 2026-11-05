import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  FunctionTarget target([ValueType? result]) => FunctionTarget(
    Uri.parse('memory:await'),
    'f',
    result ?? CoreTypes.futureOf(.integer),
    [],
  );
  IrFunction build(
    List<Block> blocks, {
    ValueType? result,
    ValueType completion = ValueType.integer,
  }) => IrFunction(
    target(result),
    blocks,
    bodyKind: .asynchronous,
    completionType: completion,
  );

  test('async completion has a separate type and can forward a future', () {
    final entry = Block()..finish(const Return(Constant.integer(1)));
    final function = build([entry]);
    expect(function.completionType, ValueType.integer);
    final text = StringBuffer();
    function.writeTo(text);
    expect('$text', contains('Future<int> async<int>'));
    expect(() => IrFunction(target(), [entry]), throwsStateError);
    expect(
      () => IrFunction(target(), [entry], completionType: .integer),
      throwsArgumentError,
    );
    expect(
      () => IrFunction(target(), [entry], bodyKind: .asynchronous),
      throwsArgumentError,
    );
    expect(() => build([entry], result: .integer), throwsArgumentError);
    final bare = Block()..finish(const Return());
    expect(() => build([bare]), throwsStateError);
    expect(
      () => build([bare], result: .voidType, completion: .voidType),
      returnsNormally,
    );
    final wrong = Block()..finish(const Return(Constant.string('bad')));
    expect(() => build([wrong]), throwsStateError);
    final argument = Block([CoreTypes.futureOf(.integer)]);
    argument.finish(Return(argument.parameters.single));
    expect(
      () => IrFunction(
        FunctionTarget(
          Uri.parse('memory:await'),
          'adopt',
          CoreTypes.futureOf(.integer),
          [CoreTypes.futureOf(.integer)],
        ),
        [argument],
        bodyKind: .asynchronous,
        completionType: .integer,
      ),
      returnsNormally,
    );
  });

  test('await has typed normal and exception resume edges', () {
    final entry = Block(),
        next = Block([.integer]),
        error = Block([.object, .stackTrace]);
    final result = AwaitResult(.integer);
    entry.finish(
      Await(
        const Constant.integer(1),
        result,
        onResume: Jump(next, [result]),
        onThrow: Jump(error, [UnwindValue.exception, UnwindValue.stackTrace]),
      ),
    );
    next.finish(Return(next.parameters.single));
    error.finish(
      Throw(error.parameters.first, stackTrace: error.parameters.last),
    );
    final function = build([entry, next, error]);
    expect(entry.successors.map((e) => e.target), [next, error]);
    final text = StringBuffer();
    function.writeTo(text);
    expect('$text', contains(': int = await 1 resume b1('));
    expect('$text', contains('unwind b2(exception, stackTrace)'));
    expect(
      () => IrFunction(target(.integer), [entry, next, error]),
      throwsStateError,
    );
    expect(() => AwaitResult(CellType(.integer)), throwsArgumentError);
    expect(
      () => Await(
        const Constant.string('bad'),
        result,
        onResume: Jump(next, [result]),
      ),
      throwsArgumentError,
    );
    expect(
      () => Await(const Constant.integer(1), result, onResume: null),
      throwsArgumentError,
    );
  });

  test('await results cannot escape their owning success edge', () {
    final entry = Block(), next = Block();
    final result = AwaitResult(.integer);
    entry.finish(
      Await(const Constant.integer(1), result, onResume: Jump(next)),
    );
    next.finish(Return(result));
    expect(() => build([entry, next]), throwsStateError);
    final first = Block(),
        resumed = Block([.integer]),
        error = Block([.integer]);
    final value = AwaitResult(.integer);
    first.finish(
      Await(
        const Constant.integer(1),
        value,
        onResume: Jump(resumed, [value]),
        onThrow: Jump(error, [value]),
      ),
    );
    resumed.finish(Return(resumed.parameters.single));
    error.finish(Return(error.parameters.single));
    expect(() => build([first, resumed, error]), throwsStateError);
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final generic = Block([t]), done = Block([t]);
    final foreign = AwaitResult(t);
    generic.finish(
      Await(
        generic.parameters.single,
        foreign,
        onResume: Jump(done, [foreign]),
      ),
    );
    done.finish(Return(done.parameters.single));
    expect(
      () => IrFunction(
        FunctionTarget(
          Uri.parse('memory:await'),
          'bad',
          CoreTypes.futureOf(t),
          [t],
        ),
        [generic, done],
        bodyKind: .asynchronous,
        completionType: t,
      ),
      throwsStateError,
    );
  });

  test('completion and await result metadata have independent type scopes', () {
    final foreign = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final futureNever = CoreTypes.futureOf(.never);
    final completionEntry = Block([futureNever]);
    completionEntry.finish(Return(completionEntry.parameters.single));
    expect(
      () => IrFunction(
        FunctionTarget(
          Uri.parse('memory:await'),
          'completionScope',
          .dynamicType,
          [futureNever],
        ),
        [completionEntry],
        bodyKind: .asynchronous,
        completionType: foreign,
      ),
      throwsStateError,
    );
    final awaitEntry = Block([.never]),
        next = Block([ValueType.object.nullable]);
    final result = AwaitResult(foreign);
    awaitEntry.finish(
      Await(
        awaitEntry.parameters.single,
        result,
        onResume: Jump(next, [result]),
      ),
    );
    next.finish(const Return(Constant.integer(1)));
    expect(
      () => IrFunction(
        FunctionTarget(
          Uri.parse('memory:await'),
          'resultScope',
          CoreTypes.futureOf(.integer),
          [.never],
        ),
        [awaitEntry, next],
        bodyKind: .asynchronous,
        completionType: .integer,
      ),
      throwsStateError,
    );
  });

  test('await results are unique and unwind values stay on error edges', () {
    final entry = Block(), next = Block(), done = Block([.integer]);
    final result = AwaitResult(.integer);
    entry.finish(
      Await(const Constant.integer(1), result, onResume: Jump(next)),
    );
    next.finish(
      Await(const Constant.integer(2), result, onResume: Jump(done, [result])),
    );
    done.finish(Return(done.parameters.single));
    expect(() => build([entry, next, done]), throwsStateError);
    final normal = Block(), invalid = Block([.object]);
    normal.finish(
      Await(
        const Constant.integer(1),
        AwaitResult(.integer),
        onResume: Jump(invalid, [UnwindValue.exception]),
      ),
    );
    invalid.finish(const Return(Constant.integer(1)));
    expect(() => build([normal, invalid]), throwsStateError);
    final never = Block([CoreTypes.futureOf(.never)]);
    expect(
      () => Await(
        never.parameters.single,
        AwaitResult(.never),
        onResume: Jump(invalid, [Constant.integer(1)]),
      ),
      throwsArgumentError,
    );
  });

  test(
    'Never await has no successful edge and can still fail into a catch',
    () {
      final future = CoreTypes.futureOf(.never);
      final entry = Block([future]), error = Block([.object, .stackTrace]);
      entry.finish(
        Await(
          entry.parameters.single,
          AwaitResult(.never),
          onResume: null,
          onThrow: Jump(error, [UnwindValue.exception, UnwindValue.stackTrace]),
        ),
      );
      error.finish(const Return(Constant.integer(1)));
      expect(
        () => IrFunction(
          FunctionTarget(
            Uri.parse('memory:await'),
            'f',
            CoreTypes.futureOf(.integer),
            [future],
          ),
          [entry, error],
          bodyKind: .asynchronous,
          completionType: .integer,
        ),
        returnsNormally,
      );
    },
  );
}
