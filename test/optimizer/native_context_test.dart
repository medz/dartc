import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _word = NativeScalarType(Int64);
final _layout = _Layout();

void main() {
  test(
    'ordinary calls inherit the actual context storage and preserve writes',
    () {
      final read = FunctionTarget(null, 'readContext', .integer, []);
      final body = Block();
      final context = body.emit(ReadNativeContext());
      body.emit(StoreNative(context, _word, const Constant.integer(37)));
      body.finish(Return(body.emit(LoadNative(context, _word))));
      final root = FunctionTarget(null, 'entry', .integer, []);
      final entry = Block();
      final local = entry.emit(NativeLocalStorage(_word, zeroInitialize: true));
      entry.emit(BindNativeContext(local));
      entry.emit(DirectCall(read, []));
      entry.finish(Return(entry.emit(LoadNative(local, _word))));
      final facts = ProgramFlow(
        IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(read, [body]),
        ]),
        [(target: root, arguments: [])],
        memoryLayout: _layout,
      ).facts;
      expect(_number(facts.returnedBy(root)), 37);
      expect(facts.valueOf(context).addresses, facts.valueOf(local).addresses);
    },
  );

  for (final throws in [false, true]) {
    test(
      'callee context restoration preserves storage writes (throws=$throws)',
      () {
        final inner = FunctionTarget(null, 'inner', .integer, [
          .integer,
          .integer,
        ]);
        final body = Block(inner.parameterTypes);
        body.emit(BindNativeContext(body.parameters[0]));
        final context = body.emit(ReadNativeContext());
        body.emit(StoreNative(context, _word, const Constant.integer(42)));
        body.emit(
          StoreNative(body.parameters[1], _word, const Constant.integer(13)),
        );
        if (throws) {
          body.finish(Throw(const Constant.string('expected')));
        } else {
          body.finish(Return(body.emit(LoadNative(context, _word))));
        }
        final root = FunctionTarget(null, 'outer', .integer, []);
        final entry = Block();
        final a = entry.emit(NativeLocalStorage(_word, zeroInitialize: true));
        final b = entry.emit(NativeLocalStorage(_word, zeroInitialize: true));
        entry.emit(BindNativeContext(a));
        final normal = Block([.integer]), failed = Block();
        final complete = Block();
        final call = DirectCall(inner, [b, a]);
        entry.finish(
          Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(failed)),
        );
        normal.finish(Jump(complete));
        failed.finish(Jump(complete));
        final restored = complete.emit(ReadNativeContext());
        complete.finish(
          Return(
            complete.emit(
              IntBinary(
                .add,
                complete.emit(LoadNative(restored, _word)),
                complete.emit(LoadNative(b, _word)),
              ),
            ),
          ),
        );
        final program = IrProgram([], [
          IrFunction(inner, [body]),
          IrFunction(root, [entry, normal, failed, complete]),
        ]);
        final facts = ProgramFlow(program, [
          (target: root, arguments: []),
        ], memoryLayout: _layout).facts;
        expect(_number(facts.returnedBy(root)), 55);
        expect(facts.valueOf(restored).addresses, facts.valueOf(a).addresses);
        final optimized =
            ProgramOptimizer(const [
              ProgramSimplification(),
              DirectCallInlining(),
            ]).run(program, [
              (target: root, arguments: []),
            ], memoryLayoutFor: (_) => _layout);
        expect(_number(optimized.returnedBy(root)), 55);
        expect(
          (optimized.program.implementationOf(
            inner,
          ) as IrFunction).observesCallerFrame,
          isTrue,
        );
      },
    );
  }

  test(
    'context reads separate caller bindings while unused context does not',
    () {
      final getter = FunctionTarget(null, 'context', .integer, []);
      final get = Block();
      get.finish(Return(get.emit(ReadNativeContext())));
      final plain = FunctionTarget(null, 'plain', .integer, []);
      final plainBody = Block()..finish(const Return(Constant.integer(3)));
      final root = FunctionTarget(null, 'bindings', .integer, []);
      final entry = Block();
      entry.emit(BindNativeContext(const Constant.integer(10)));
      final first = entry.emit(DirectCall(getter, []));
      entry.emit(DirectCall(plain, []));
      entry.emit(BindNativeContext(const Constant.integer(20)));
      final second = entry.emit(DirectCall(getter, []));
      entry.emit(DirectCall(plain, []));
      entry.finish(Return(entry.emit(IntBinary(.add, first, second))));
      final facts = ProgramFlow(
        IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(getter, [get]),
          IrFunction(plain, [plainBody]),
        ]),
        [(target: root, arguments: [])],
      ).facts;
      expect(_number(facts.returnedBy(root)), 30);
      expect(facts.activationsOf(getter), hasLength(2));
      expect(facts.activationsOf(plain), hasLength(1));
    },
  );
}

Object? _number(FlowValue value) => (value.constant as ScalarConstant?)?.value;

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .arm64));

  @override
  ObjectLayout objectLayout(ClassType type) =>
      throw StateError('No managed storage in this program.');
}
