import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test('native context read and binding have exact nonallocating effects', () {
    final read = ReadNativeContext();
    final bind = BindNativeContext(const Constant.integer(7));
    expect(read.type, ValueType.integer);
    expect(read.effects, {Effect.readsStorage});
    expect(bind.type, ValueType.voidType);
    expect(bind.effects, {Effect.writesStorage});
    expect(read.mayThrow, isFalse);
    expect(bind.mayThrow, isFalse);
    expect(
      () => BindNativeContext(const Constant.nullValue()),
      throwsArgumentError,
    );
    final copy =
        bind.mapInputs((_) => const Constant.integer(9)) as BindNativeContext;
    expect(copy.address, const Constant.integer(9));
    final target = FunctionTarget(null, 'context', .integer, []);
    final readBody = Block();
    readBody.finish(Return(readBody.emit(ReadNativeContext())));
    expect(IrFunction(target, [readBody]).observesCallerFrame, isFalse);
    final body = Block();
    body.emit(bind);
    body.emit(copy);
    body.finish(Return(body.emit(ReadNativeContext())));
    final function = IrFunction(target, [body]);
    expect(function.observesCallerFrame, isTrue);
    final text = StringBuffer();
    function.writeTo(text);
    expect(text.toString(), contains('bindNativeContext 7'));
    expect(text.toString(), contains('readNativeContext'));
    final asyncBody = Block()
      ..emit(BindNativeContext(const Constant.integer(1)));
    asyncBody.finish(const Return());
    expect(
      () => IrFunction(
        FunctionTarget(null, 'asyncBinding', CoreTypes.futureOf(.nullType), []),
        [asyncBody],
        bodyKind: .asynchronous,
        completionType: ValueType.nullType,
      ),
      throwsStateError,
    );
  });
}
