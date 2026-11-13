import 'dart:ffi';

import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  test(
    'asFunction creates typed lexical bodies with native call contracts',
    () async {
      final result = await AnalysisSession([
        'test/frontend/lowering/fixtures/ffi_functions.dart',
        'test/frontend/lowering/fixtures/ffi_constant_leaf.dart',
      ]).use(Lowering().lower);
      final adapters = result.program.functions.where(
        (f) => f.target.name == '<native-function>',
      );
      expect(adapters, isNotEmpty);
      expect(
        adapters.where((f) => f.target.enclosing?.name == 'cleanup'),
        hasLength(1),
      );
      for (final adapter in adapters) {
        expect(adapter.target.kind, FunctionKind.closure);
        expect(adapter.target.captures, hasLength(1));
        final name = adapter.target.enclosing?.name;
        expect(adapter.target.signature, switch (name) {
          'floating' => FunctionType(.floating, [.floating]),
          'empty' => FunctionType(.voidType, []),
          'widenedPointer' => FunctionType(
            FfiTypes.pointer.instantiate([FfiTypes.nativeType]),
            [FfiTypes.int64Pointer],
          ),
          _ => FunctionType(.integer, [.integer]),
        });
        final call = adapter.entry.instructions.whereType<NativeCall>().single;
        expect(call.signature, switch (name) {
          'floating' => NativeSignature(Float, [Double]),
          'empty' => NativeSignature(Void, []),
          'widenedPointer' => NativeSignature(Pointer<Int64>, [Pointer<Int64>]),
          _ => NativeSignature(Int64, [Int8]),
        });
        expect(call.pointer, same(adapter.entry.parameters[1]));
        expect(
          call.isLeaf,
          ['leaf', 'constantLeaf'].contains(adapter.target.enclosing?.name),
        );
      }
      expect(
        result.program.externals.any(
          (f) =>
              f.target.library.toString() == 'dart:ffi' &&
              f.target.name.endsWith('asFunction'),
        ),
        isFalse,
      );
    },
  );

  test(
    'unused FFI declarations retain signature, constant and layout obligations',
    () async {
      for (final name in [
        'invalid_ffi_functions',
        'invalid_variable_array',
        'invalid_ffi_callback',
        'invalid_ffi_generic_callback',
        'invalid_ffi_callable',
      ]) {
        var consumed = false;
        await expectLater(
          AnalysisSession(['test/frontend/lowering/fixtures/$name.dart'])
              .use((_) => consumed = true),
          throwsFormatException,
        );
        expect(consumed, isFalse);
      }
    },
  );

  test(
    'function pointer exports retain nested FFI identities through lowering',
    () async {
      final result = await AnalysisSession([
        'test/compiler/fixtures/native_function_pointers.dart',
      ]).use(Lowering().lower);
      final functions = {
        for (final f in result.program.functions)
          if (f.target.owner == null) f.target.name: f,
      };
      final factory = result.exports.entries.singleWhere(
        (e) => e.key.name == 'identity',
      );
      final callback = NativePointerType(
        NativeFunctionType(NativeSignature(Int64, [Int8])),
      );
      expect(
        factory.value.signature,
        NativeSignature.types(callback, [callback]),
      );
      expect(factory.key.returnType, FfiTypes.resolve(callback));
      final runner = IrInterpreter(result.program, {});
      final a = runner.run(functions['fromAddress']!, [0x1000]);
      final b = runner.run(functions['fromAddress']!, [0x2000]);
      expect(
        runner.run(functions['sameAddress']!, [
          a,
          Pointer<Void>.fromAddress(0x1000),
        ]),
        1,
      );
      expect(
        runner.run(functions['differentAddress']!, [
          Pointer<Void>.fromAddress(0x1000),
          a,
        ]),
        0,
      );
      expect(
        runner.run(functions['address']!, [
          runner.run(functions['identity']!, [a]),
        ]),
        0x1000,
      );
      for (final count in [-1, 0, 1, 2, 5]) {
        final chosen = runner.run(functions['select']!, [
          a,
          a,
          b,
          b,
          a,
          a,
          b,
          b,
          b,
          b,
          count,
        ]);
        expect(
          runner.run(functions['address']!, [chosen]),
          count < 0 || count.isOdd ? 0x2000 : 0x1000,
        );
      }
    },
  );

  test(
    'FFI lowering uses declarations, preserving user classes and extensions',
    () async {
      final result = await AnalysisSession([
        'test/compiler/fixtures/pointers.dart',
        'test/compiler/fixtures/pointer_helpers.dart',
      ]).use(Lowering().lower);
      final functions = {
        for (final function in result.program.functions)
          if (function.target.owner == null) function.target.name: function,
      };
      Iterable<Instruction> instructions(String name) =>
          functions[name]!.blocks.expand((block) => block.instructions);
      expect(
        instructions('fromAddress').whereType<PointerFromAddress>(),
        hasLength(1),
      );
      expect(instructions('address').whereType<PointerAddress>(), hasLength(1));
      expect(instructions('read').whereType<LoadNative>(), hasLength(1));
      expect(instructions('write').whereType<StoreNative>(), hasLength(1));
      final slot = functions['exchangeSlot']!;
      final element = (slot.target.signature.parameters.first as ClassType)
          .typeArguments
          .single;
      expect(slot.target.returnType, element);
      expect(
        instructions('exchangeSlot')
            .whereType<PointerFromAddress>()
            .single
            .type,
        element,
      );
      expect(
        instructions('exchangeSlot').whereType<LoadNative>().single.nativeType,
        NativeScalarType(Uint64),
      );
      expect(
        result.program.externals.any(
          (f) => f.target.name.startsWith('PointerPointer.'),
        ),
        isFalse,
      );
      final bounded = instructions('boundedWrite').toList();
      expect(bounded.whereType<PointerFromAddress>(), hasLength(2));
      expect(bounded.whereType<PointerOffset>(), hasLength(2));
      expect(
        bounded.whereType<StoreNative>().every(
          (store) => store.address.type == .integer,
        ),
        isTrue,
      );
      expect(
        bounded.whereType<StoreNative>().map((store) => store.value.type),
        [
          ...List.filled(4, ValueType.integer),
          ...List.filled(2, ValueType.floating),
        ],
      );
      expect(
        instructions('ordinaryPointer').whereType<Construct>(),
        hasLength(1),
      );
      expect(
        instructions('customMember').whereType<DirectCall>(),
        hasLength(1),
      );
      expect(instructions('customMember').whereType<LoadNative>(), isEmpty);
      for (final name in ['customOffset', 'customIndex']) {
        expect(instructions(name).whereType<PointerOffset>(), isEmpty);
        expect(instructions(name).whereType<DirectCall>(), hasLength(1));
      }
      final runner = IrInterpreter(result.program, {});
      for (final address in [
        0,
        1,
        -1,
        -9223372036854775808,
        9223372036854775807,
      ]) {
        final pointer = runner.run(functions['fromAddress']!, [address]);
        expect(pointer, Pointer<Int64>.fromAddress(address));
        expect(runner.run(functions['address']!, [pointer]), address);
        expect(runner.run(functions['declaredMember']!, [pointer]), 73);
        expect(runner.run(functions['ordinaryPointer']!, [address]), address);
        expect(runner.run(functions['customOffset']!, [pointer]), address);
        expect(runner.run(functions['customIndex']!, [pointer]), 77);
      }
    },
  );
}
