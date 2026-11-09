import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:test/test.dart';

void main() {
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
    expect(signature.result, Void);
    expect(signature.parameters, [Pointer<Int64>, Int64]);
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
    for (final type in <Type>[Void, IntPtr, Pointer<Void>, int]) {
      expect(() => NativeSignature(Int64, [type]), throwsUnsupportedError);
      if (type != Void) {
        expect(() => NativeSignature(type, []), throwsUnsupportedError);
      }
    }
  });
}
