import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ABI integer mappings reject non-integer storage and require a target',
    () {
      for (final type in [Bool, Float, Double, IntPtr, Void]) {
        expect(
          () => NativeAbiIntegerType(
            Uri.parse('package:example/types.dart'),
            'Integer',
            {Abi.macosArm64: NativeScalarType(type)},
          ),
          throwsArgumentError,
        );
      }
      final mapping = {Abi.macosArm64: NativeScalarType(Int8)};
      final type = NativeAbiIntegerType(
        Uri.parse('package:example/types.dart'),
        'Integer',
        mapping,
      );
      mapping.clear();
      expect(type.resolveAbi(Abi.macosArm64), NativeScalarType(Int8));
      expect(() => type.resolveAbi(Abi.linuxArm64), throwsUnsupportedError);
      expect(() => type.declaration('value'), throwsArgumentError);
      expect(type.declaration('value', abi: Abi.macosArm64), 'int8_t value');
    },
  );
  test('nested function pointers retain complete types and C declarators', () {
    final callback = NativePointerType(
      NativeFunctionType(NativeSignature(Int64, [Int8])),
    );
    final signature = NativeSignature.types(callback, [callback]);
    final equivalent = NativeSignature.types(
      NativePointerType(NativeFunctionType(NativeSignature(Int64, [Int8]))),
      [callback],
    );
    expect(signature, equivalent);
    expect(signature.hashCode, equivalent.hashCode);
    expect(callback.nativeSize, 8);
    expect(callback.isFloating, isFalse);
    expect(callback.integerLayout, isNull);
    expect(callback.toString(), 'int64_t (*)(int8_t)');
    expect(
      signature.declaration('identity'),
      'int64_t (*identity(int64_t (*)(int8_t)))(int8_t)',
    );
    final factory = NativePointerType(NativeFunctionType(signature));
    expect(
      NativeSignature.types(factory, [factory]).declaration('nested'),
      'int64_t (*(*nested(int64_t (*(*)(int64_t (*)(int8_t)))(int8_t)))(int64_t (*)(int8_t)))(int8_t)',
    );
    expect(
      NativeSignature(Pointer<Void>, [Pointer<Void>]).declaration('opaque'),
      'void* opaque(void*)',
    );
    expect(
      NativePointerType(NativePointerType(NativeScalarType(Int64)))
          .declaration('p'),
      'int64_t* * p',
    );
    expect(
      callback,
      isNot(
        NativePointerType(NativeFunctionType(NativeSignature(Int64, [Uint8]))),
      ),
    );
  });

  test(
    'unsized native function markers cannot occupy parameters or results',
    () {
      final function = NativeFunctionType(NativeSignature(Void, []));
      expect(() => function.nativeSize, throwsUnsupportedError);
      expect(() => NativeSignature.types(function, []), throwsUnsupportedError);
      expect(
        () => NativeSignature.types(NativeScalarType(Void), [function]),
        throwsUnsupportedError,
      );
      expect(() => NativeScalarType(Pointer<Int64>), throwsUnsupportedError);
    },
  );

  test('native imports reject invalid symbol strings', () {
    final signature = NativeSignature(Int8, [Float]);
    for (final symbol in ['', 'bad\u0000symbol']) {
      expect(() => NativeImport(symbol, signature), throwsArgumentError);
    }
  });

  test('floating signatures preserve storage widths and C declarations', () {
    for (final (type, pointer, bytes, name) in [
      (Float, Pointer<Float>, 4, 'float'),
      (Double, Pointer<Double>, 8, 'double'),
    ]) {
      final output = StringBuffer();
      NativeExport(
        'access',
        NativeSignature(type, [pointer, type]),
      ).writeDeclaration(output);
      expect(output.toString(), '$name access($name*, $name);\n');
      expect(type.isFloating, isTrue);
      expect(type.nativeSize, bytes);
      expect(type.pointerType, pointer);
      expect(pointer.pointerElement, type);
      expect(pointer.nativeSize, 8);
      expect(pointer.isFloating, isFalse);
    }
    expect((Int32).isFloating, isFalse);
  });

  test('integer declarations preserve widths, signs and pointer elements', () {
    for (final (type, bytes, signed, pointer) in [
      (Int8, 1, true, Pointer<Int8>),
      (Uint8, 1, false, Pointer<Uint8>),
      (Int16, 2, true, Pointer<Int16>),
      (Uint16, 2, false, Pointer<Uint16>),
      (Int32, 4, true, Pointer<Int32>),
      (Uint32, 4, false, Pointer<Uint32>),
      (Int64, 8, true, Pointer<Int64>),
      (Uint64, 8, false, Pointer<Uint64>),
    ]) {
      final output = StringBuffer();
      NativeExport(
        'access',
        NativeSignature(type, [pointer, type]),
      ).writeDeclaration(output);
      final name = '${signed ? '' : 'u'}int${bytes * 8}_t';
      expect(output.toString(), '$name access($name*, $name);\n');
      expect(pointer.pointerElement, type);
      expect(type.nativeSize, bytes);
      expect(pointer.nativeSize, 8);
    }
  });

  test('signatures own their supported FFI parameter types', () {
    final parameters = <Type>[Pointer<Int64>, Int64];
    final signature = NativeSignature(Void, parameters);
    parameters.clear();
    expect(signature.result, NativeTypeRef.of(Void));
    expect(signature.parameters, [Pointer<Int64>, Int64].map(NativeTypeRef.of));
    expect(() => signature.parameters.clear(), throwsUnsupportedError);
    final output = StringBuffer();
    NativeExport('write', signature).writeDeclaration(output);
    NativeExport(
      'address',
      NativeSignature(Pointer<Int64>, [Int64]),
    ).writeDeclaration(output);
    expect(
      output.toString(),
      'void write(int64_t*, int64_t);\nint64_t* address(int64_t);\n',
    );
  });

  test('unsupported native types cannot reach ABI classification', () {
    for (final type in <Type>[Void, int]) {
      expect(() => NativeSignature(Int64, [type]), throwsUnsupportedError);
      if (type != Void) {
        expect(() => NativeSignature(type, []), throwsUnsupportedError);
      }
    }
  });
}
