import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const n = Constant.integer(1);
  final uri = Uri.parse('memory:effects');
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
}
