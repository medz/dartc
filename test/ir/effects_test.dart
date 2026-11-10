import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const n = Constant.integer(1);
  final uri = Uri.parse('memory:effects');
  test('non-covariant field results can throw before their value is used', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final owner = ClassType(uri, 'Callbacks', typeParameters: [t]);
    final callback = FunctionType(.boolean, [t]);
    final field = InstanceField(owner, 'callback', callback);
    final getter = FunctionTarget(
      uri,
      'callback',
      callback,
      [],
      owner: owner,
      kind: .getter,
    );
    final receiver = Block([
      owner.instantiate([.number]),
    ]).parameters.single;
    expect(field.requiresReadCheck, isTrue);
    expect(getter.requiresResultCheck, isTrue);
    expect(callback.requiresCovariantCheck({t}), isFalse);
    expect(LoadField(field, receiver).effects, {
      Effect.readsStorage,
      Effect.mayThrow,
    });
    expect(InstanceField(owner, 'value', t).requiresReadCheck, isFalse);
  });
  test('ordinary storage, lazy initialization and arbitrary calls stay distinguishable', () {
    final owner = ClassType(uri, 'C');
    final slot = InstanceField(owner, 'value', .integer);
    final receiver = Block([owner]).parameters.single;
    final lazy = GlobalVariable(
      uri,
      'lazy',
      .integer,
      initializer: FunctionTarget(uri, 'init', .integer, []),
    );
    final plain = GlobalVariable(uri, 'plain', ValueType.integer.nullable);
    expect(IntBinary(.add, n, n).effects, isEmpty);
    expect(ObjectRuntimeType(n).effects, Effect.values.toSet());
    expect(ObjectRuntimeType(n, direct: true).effects, {Effect.readsStorage});
    expect(
      () => ObjectRuntimeType(NewCell(CellType(.integer), n)),
      throwsArgumentError,
    );
    expect(IntBinary(.truncateDivide, n, n).effects, {Effect.mayThrow});
    expect(LoadField(slot, receiver).effects, {Effect.readsStorage});
    expect(StoreField(slot, receiver, n).effects, {Effect.writesStorage});
    expect(LoadGlobal(plain).effects, {Effect.readsStorage});
    expect(LoadGlobal(lazy).effects, Effect.values.toSet());
    expect(DirectCall(lazy.initializer!, []).effects, Effect.values.toSet());
    expect(NewCell(CellType(.integer), n).effects, {
      Effect.allocates,
      Effect.mayThrow,
    });
    expect(Equals(n, n).effects, isEmpty);
    expect(Equals(receiver, receiver).effects, contains(Effect.callsUserCode));
    expect(() => LoadGlobal(lazy).effects.clear(), throwsUnsupportedError);
  });
  test(
    'writing through a widened generic receiver can reach a Dart handler',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final box = ClassType(uri, 'Box', typeParameters: [t]);
      final value = InstanceField(box, 'value', t);
      final ctor = FunctionTarget(
        uri,
        'new',
        .voidType,
        [t],
        owner: box,
        kind: .initializer,
      );
      final init = Block(ctor.parameterTypes);
      init.emit(StoreField(value, init.parameters.first, init.parameters.last));
      init.finish(const Return());
      final entry = Block();
      final narrow = entry.emit(
        Construct(ctor, [
          n,
        ], instantiatedType: box.instantiate([ValueType.integer])),
      );
      final wide = entry.emit(
        TypeView(narrow, box.instantiate([ValueType.number])),
      );
      final store = StoreField(value, wide, const Constant.floating(1.5));
      expect(store.effects, {Effect.writesStorage, Effect.mayThrow});
      final done = Block()..finish(const Return(Constant.boolean(false)));
      final error = Block([.object, .stackTrace]);
      error.finish(
        Return(error.emit(TypeTest(error.parameters.first, .typeError))),
      );
      entry.finish(
        Invoke(
          store,
          onReturn: Jump(done),
          onThrow: Jump(error, [UnwindValue.exception, UnwindValue.stackTrace]),
        ),
      );
      final function = IrFunction(FunctionTarget(uri, 'store', .boolean, []), [
        entry,
        done,
        error,
      ]);
      final program = IrProgram(
        [
          IrClass(box, [value], constructors: [ctor]),
        ],
        [
          IrFunction(ctor, [init]),
          function,
        ],
      );
      expect(IrInterpreter(program, {}).run(function, []), isTrue);
    },
  );
  test('ordinary and late callback reads check the receiver view', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final owner = ClassType(uri, 'Callbacks', typeParameters: [t]);
    final callback = FunctionType(.boolean, [t]);
    final target = FunctionTarget(uri, 'accept', .boolean, [.integer]);
    final implementation = IrFunction(target, [
      Block(target.parameterTypes)
        ..finish(const Return(Constant.boolean(true))),
    ]);
    for (final late in [false, true]) {
      final field = InstanceField(owner, 'callback', callback, isLate: late);
      final ctor = FunctionTarget(
        uri,
        'new',
        .voidType,
        [callback],
        owner: owner,
        kind: .initializer,
      );
      final init = Block(ctor.parameterTypes);
      init.emit(StoreField(field, init.parameters.first, init.parameters.last));
      init.finish(const Return());
      for (final type in [ValueType.integer, ValueType.number]) {
        final entry = Block();
        final instance = entry.emit(
          Construct(ctor, [
            FunctionConstant(target),
          ], instantiatedType: owner.instantiate([.integer])),
        );
        final receiver = entry.emit(
          TypeView(instance, owner.instantiate([type])),
        );
        final done = Block()..finish(const Return(Constant.boolean(false)));
        final failed = Block([.object]);
        failed.finish(
          Return(failed.emit(TypeTest(failed.parameters.single, .typeError))),
        );
        entry.finish(
          Invoke(
            LoadField(field, receiver),
            onReturn: Jump(done),
            onThrow: Jump(failed, [UnwindValue.exception]),
          ),
        );
        final function = IrFunction(FunctionTarget(uri, 'read', .boolean, []), [
          entry,
          done,
          failed,
        ]);
        final program = IrProgram(
          [
            IrClass(owner, [field], constructors: [ctor]),
          ],
          [
            implementation,
            IrFunction(ctor, [init]),
            function,
          ],
        );
        expect(
          IrInterpreter(program, {}).run(function, []),
          type == ValueType.number,
        );
      }
    }
  });
}
