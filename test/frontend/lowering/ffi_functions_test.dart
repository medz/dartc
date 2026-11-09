@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../../compiler/fixtures/native_function_pointers_ffi.dart';
import '../../support/ir_interpreter.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/ffi_functions.dart' as sdk;

void main() {
  late NativeFunctionPointers library;
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  final nativeCalls = <(int, bool)>[];

  setUpAll(() async {
    library = NativeFunctionPointers();
    addTearDown(library.close);
    final result = await AnalysisSession([
      'test/frontend/lowering/fixtures/ffi_functions.dart',
      'test/frontend/lowering/fixtures/ffi_constant_leaf.dart',
    ]).use(Lowering().lower);
    functions = {for (final f in result.program.functions) f.target.name: f};
    runner = IrInterpreter(
      result.program,
      {
        (
          Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
          'tick',
        ): effects.tick,
        (
          Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
          'probe',
        ): effects.probe,
      },
      callNative: (call, address, arguments) {
        expect(call.signature, NativeSignature(Int64, [Int8]));
        nativeCalls.add((address, call.isLeaf));
        final pointer = sdk.FunctionPointer.fromAddress(address);
        final invoke = call.isLeaf
            ? pointer.asFunction<sdk.DartUnary>(isLeaf: true)
            : pointer.asFunction<sdk.DartUnary>();
        return invoke(arguments.single as int);
      },
    );
  });
  setUp(() {
    effects.calls.clear();
    nativeCalls.clear();
  });
  Object? run(String name, List<Object?> args) =>
      runner.run(functions[name]!, args);

  test('returned functions retain addresses, types and leaf promises after capture', () {
    for (final (pointer, delta) in [
      (library.increment, 7),
      (library.decrement, -11),
    ]) {
      final address = pointer.address;
      for (final (name, create) in <(String, sdk.DartUnary Function(int))>[
        ('bind', sdk.bind),
        ('inferred', sdk.inferred),
        ('leaf', sdk.leaf),
        ('nested', sdk.nested),
      ]) {
        final function = run(name, [address]);
        final expected = create(address);
        for (final value in [-129, 0, 129, 255]) {
          expect(expected(value), value.toSigned(8) + delta);
          expect(run('invoke', [function, value]), value.toSigned(8) + delta);
          expect(run('dynamicInvoke', [function, value]), expected(value));
          expect(nativeCalls.last, (address, name == 'leaf'));
        }
      }
      final other = pointer == library.increment
          ? library.decrement
          : library.increment;
      final captured = run('capture', [address, other.address]);
      expect(run('invoke', [captured, 129]), -127 + delta);
      expect(sdk.capture(address, other.address)(129), -127 + delta);
    }
  });

  test('isLeaf accepts an evaluated constant expression', () {
    final address = library.increment.address;
    final function = run('constantLeaf', [address]);
    expect(run('invoke', [function, 129]), -120);
    expect(nativeCalls, [(address, true)]);
  });

  test(
    'stored functions survive control-flow selection and repeated calls',
    () {
      final first = library.increment.address,
          second = library.decrement.address;
      for (final choose in [true, false]) {
        for (final count in [0, 1, 5]) {
          const value = 127;
          final expected =
              value +
              (choose ? 7 : -11) +
              [
                for (var i = 0; i < count; i++)
                  (value + i).toSigned(8) + (i.isEven ? 7 : -11),
              ].fold(0, (sum, value) => sum + value);
          expect(sdk.saved(first, second, choose, count, value), expected);
          expect(run('saved', [first, second, choose, count, value]), expected);
        }
      }
    },
  );

  test(
    'binding, null-aware calls, cleanup and argument failures preserve order',
    () {
      final address = library.increment.address;
      expect(run('ordered', [address, 129]), -120);
      expect(effects.calls, [1, 129]);
      expect(nativeCalls, [(address, false)]);
      effects.calls.clear();
      nativeCalls.clear();
      expect(() => run('ordered', [address, -1]), throwsStateError);
      expect(effects.calls, [1, -1]);
      expect(nativeCalls, isEmpty);
      effects.calls.clear();
      expect(run('nullableCall', [0, 129]), -1);
      expect(effects.calls, isEmpty);
      expect(nativeCalls, isEmpty);
      expect(run('nullableCall', [address, 129]), -120);
      expect(effects.calls, [129]);
      for (final value in [0, 1]) {
        effects.calls.clear();
        expect(run('cleanup', [address, value]), value == 0 ? 7 : 9);
        expect(effects.calls, [8]);
      }
      nativeCalls.clear();
      effects.calls.clear();
      expect(run('custom', [11]), sdk.custom(11));
      expect(effects.calls, [2, 2]);
      expect(nativeCalls, isEmpty);
    },
  );
}
