import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:test/test.dart';

void main() {
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
    for (final type in <Type>[Void, Float, Int32, Pointer<Int8>, int]) {
      expect(() => NativeSignature(Int64, [type]), throwsUnsupportedError);
      if (type != Void) {
        expect(() => NativeSignature(type, []), throwsUnsupportedError);
      }
    }
  });
}
