import 'package:dartc/src/emit/x64/assembler.dart';
import 'package:test/test.dart';

/// Bytes produced by the system assembler for the same instructions.
void _encodes(String bytes, void Function(X64Assembler assembler) emit) {
  final assembler = X64Assembler();
  emit(assembler);
  final made = [
    for (final byte in assembler.finish())
      byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  expect(made, bytes);
}

void main() {
  test('instructions', () {
    _encodes('4801c8', (a) => a.binary(.add, 0, 1));
    _encodes('4901dc', (a) => a.binary(.add, 12, 3));
    _encodes('4c01e3', (a) => a.binary(.add, 3, 12));
    _encodes('4d01fd', (a) => a.binary(.add, 13, 15));
    _encodes('4801fe', (a) => a.binary(.add, 6, 7));
    _encodes('4809c8', (a) => a.binary(.or, 0, 1));
    _encodes('4909dc', (a) => a.binary(.or, 12, 3));
    _encodes('4c09e3', (a) => a.binary(.or, 3, 12));
    _encodes('4d09fd', (a) => a.binary(.or, 13, 15));
    _encodes('4809fe', (a) => a.binary(.or, 6, 7));
    _encodes('4821c8', (a) => a.binary(.and, 0, 1));
    _encodes('4921dc', (a) => a.binary(.and, 12, 3));
    _encodes('4c21e3', (a) => a.binary(.and, 3, 12));
    _encodes('4d21fd', (a) => a.binary(.and, 13, 15));
    _encodes('4821fe', (a) => a.binary(.and, 6, 7));
    _encodes('4829c8', (a) => a.binary(.sub, 0, 1));
    _encodes('4929dc', (a) => a.binary(.sub, 12, 3));
    _encodes('4c29e3', (a) => a.binary(.sub, 3, 12));
    _encodes('4d29fd', (a) => a.binary(.sub, 13, 15));
    _encodes('4829fe', (a) => a.binary(.sub, 6, 7));
    _encodes('4831c8', (a) => a.binary(.xor, 0, 1));
    _encodes('4931dc', (a) => a.binary(.xor, 12, 3));
    _encodes('4c31e3', (a) => a.binary(.xor, 3, 12));
    _encodes('4d31fd', (a) => a.binary(.xor, 13, 15));
    _encodes('4831fe', (a) => a.binary(.xor, 6, 7));
    _encodes('4839c8', (a) => a.binary(.cmp, 0, 1));
    _encodes('4939dc', (a) => a.binary(.cmp, 12, 3));
    _encodes('4c39e3', (a) => a.binary(.cmp, 3, 12));
    _encodes('4d39fd', (a) => a.binary(.cmp, 13, 15));
    _encodes('4839fe', (a) => a.binary(.cmp, 6, 7));
    _encodes('4885c8', (a) => a.binary(.test, 0, 1));
    _encodes('4985dc', (a) => a.binary(.test, 12, 3));
    _encodes('4c85e3', (a) => a.binary(.test, 3, 12));
    _encodes('4d85fd', (a) => a.binary(.test, 13, 15));
    _encodes('4885fe', (a) => a.binary(.test, 6, 7));
    _encodes('4889c8', (a) => a.binary(.mov, 0, 1));
    _encodes('4989dc', (a) => a.binary(.mov, 12, 3));
    _encodes('4c89e3', (a) => a.binary(.mov, 3, 12));
    _encodes('4d89fd', (a) => a.binary(.mov, 13, 15));
    _encodes('4889fe', (a) => a.binary(.mov, 6, 7));
    _encodes('48f7d8', (a) => a.unary(.neg, 0));
    _encodes('48f7df', (a) => a.unary(.neg, 7));
    _encodes('49f7dc', (a) => a.unary(.neg, 12));
    _encodes('48f7f8', (a) => a.unary(.idiv, 0));
    _encodes('48f7ff', (a) => a.unary(.idiv, 7));
    _encodes('49f7fc', (a) => a.unary(.idiv, 12));
    _encodes('48d3e0', (a) => a.unary(.shl, 0));
    _encodes('48d3e7', (a) => a.unary(.shl, 7));
    _encodes('49d3e4', (a) => a.unary(.shl, 12));
    _encodes('48d3e8', (a) => a.unary(.shr, 0));
    _encodes('48d3ef', (a) => a.unary(.shr, 7));
    _encodes('49d3ec', (a) => a.unary(.shr, 12));
    _encodes('48d3f8', (a) => a.unary(.sar, 0));
    _encodes('48d3ff', (a) => a.unary(.sar, 7));
    _encodes('49d3fc', (a) => a.unary(.sar, 12));
    _encodes('ffd0', (a) => a.unary(.call, 0));
    _encodes('ffd7', (a) => a.unary(.call, 7));
    _encodes('41ffd4', (a) => a.unary(.call, 12));
    _encodes('ffe0', (a) => a.unary(.jmp, 0));
    _encodes('ffe7', (a) => a.unary(.jmp, 7));
    _encodes('41ffe4', (a) => a.unary(.jmp, 12));
    _encodes('480fafc1', (a) => a.imul(0, 1));
    _encodes('4c0fafe3', (a) => a.imul(12, 3));
    _encodes('490fafdc', (a) => a.imul(3, 12));
    _encodes('4899', (a) => a.cqo());
    _encodes('4883c1ff', (a) => a.binaryImmediate(.add, 1, -1));
    _encodes('4983c37f', (a) => a.binaryImmediate(.add, 11, 127));
    _encodes('4981c3e8030000', (a) => a.binaryImmediate(.add, 11, 1000));
    _encodes('4881c490eefeff', (a) => a.binaryImmediate(.add, 4, -70000));
    _encodes('4883c9ff', (a) => a.binaryImmediate(.or, 1, -1));
    _encodes('4983cb7f', (a) => a.binaryImmediate(.or, 11, 127));
    _encodes('4981cbe8030000', (a) => a.binaryImmediate(.or, 11, 1000));
    _encodes('4881cc90eefeff', (a) => a.binaryImmediate(.or, 4, -70000));
    _encodes('4883e1ff', (a) => a.binaryImmediate(.and, 1, -1));
    _encodes('4983e37f', (a) => a.binaryImmediate(.and, 11, 127));
    _encodes('4981e3e8030000', (a) => a.binaryImmediate(.and, 11, 1000));
    _encodes('4881e490eefeff', (a) => a.binaryImmediate(.and, 4, -70000));
    _encodes('4883e9ff', (a) => a.binaryImmediate(.sub, 1, -1));
    _encodes('4983eb7f', (a) => a.binaryImmediate(.sub, 11, 127));
    _encodes('4981ebe8030000', (a) => a.binaryImmediate(.sub, 11, 1000));
    _encodes('4881ec90eefeff', (a) => a.binaryImmediate(.sub, 4, -70000));
    _encodes('4883f1ff', (a) => a.binaryImmediate(.xor, 1, -1));
    _encodes('4983f37f', (a) => a.binaryImmediate(.xor, 11, 127));
    _encodes('4981f3e8030000', (a) => a.binaryImmediate(.xor, 11, 1000));
    _encodes('4881f490eefeff', (a) => a.binaryImmediate(.xor, 4, -70000));
    _encodes('4883f9ff', (a) => a.binaryImmediate(.cmp, 1, -1));
    _encodes('4983fb7f', (a) => a.binaryImmediate(.cmp, 11, 127));
    _encodes('4981fbe8030000', (a) => a.binaryImmediate(.cmp, 11, 1000));
    _encodes('4881fc90eefeff', (a) => a.binaryImmediate(.cmp, 4, -70000));
    _encodes('4881ec00100000', (a) => a.subStack(4096));
    _encodes('4883e4f0', (a) => a.alignStack());
    _encodes('48c1e005', (a) => a.shiftImmediate(.shl, 0, 5));
    _encodes('49c1e105', (a) => a.shiftImmediate(.shl, 9, 5));
    _encodes('48c1e805', (a) => a.shiftImmediate(.shr, 0, 5));
    _encodes('49c1e905', (a) => a.shiftImmediate(.shr, 9, 5));
    _encodes('48c1f805', (a) => a.shiftImmediate(.sar, 0, 5));
    _encodes('49c1f905', (a) => a.shiftImmediate(.sar, 9, 5));
    _encodes('4969c9e8030000', (a) => a.imulImmediate(1, 9, 1000));
    _encodes('4c69c990eefeff', (a) => a.imulImmediate(9, 1, -70000));
    _encodes(
      '4a8d4cca18',
      (a) => a.lea(1, const Memory(2, offset: 24, index: 9, isScaled: true)),
    );
    _encodes(
      '4d8b54c500',
      (a) => a.load(10, const Memory(13, index: 0, isScaled: true)),
    );
    _encodes('488d10', (a) => a.lea(2, const Memory(0)));
    _encodes('488d5308', (a) => a.lea(2, const Memory(3, offset: 8)));
    _encodes('488d1424', (a) => a.lea(2, const Memory(4)));
    _encodes('488d542408', (a) => a.lea(2, const Memory(4, offset: 8)));
    _encodes('488d5500', (a) => a.lea(2, const Memory(5)));
    _encodes('488d55f8', (a) => a.lea(2, const Memory(5, offset: -8)));
    _encodes('498d1424', (a) => a.lea(2, const Memory(12)));
    _encodes('4d8d5c2410', (a) => a.lea(11, const Memory(12, offset: 16)));
    _encodes('498d5500', (a) => a.lea(2, const Memory(13)));
    _encodes(
      '4d8d9de8030000',
      (a) => a.lea(11, const Memory(13, offset: 1000)),
    );
    _encodes('4d8d987fffffff', (a) => a.lea(11, const Memory(8, offset: -129)));
    _encodes('488d507f', (a) => a.lea(2, const Memory(0, offset: 127)));
    _encodes('488d9080000000', (a) => a.lea(2, const Memory(0, offset: 128)));
    _encodes('488d1411', (a) => a.lea(2, const Memory(1, index: 2)));
    _encodes(
      '4a8d541108',
      (a) => a.lea(2, const Memory(1, offset: 8, index: 10)),
    );
    _encodes('4b8d142c', (a) => a.lea(2, const Memory(12, index: 13)));
    _encodes('4b8d542500', (a) => a.lea(2, const Memory(13, index: 12)));
    _encodes('488d540d00', (a) => a.lea(2, const Memory(5, index: 1)));
    _encodes(
      '488d540cf8',
      (a) => a.lea(2, const Memory(4, offset: -8, index: 1)),
    );
    _encodes(
      '4f8d9c37ffffff7f',
      (a) => a.lea(11, const Memory(15, offset: 2147483647, index: 14)),
    );
    _encodes(
      '480fbe4b08',
      (a) => a.loadWidth(.i8, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '4a0fbe4c1108',
      (a) => a.loadWidth(.i8, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '4c0fbe4b08',
      (a) => a.loadWidth(.i8, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '4e0fbe4c1108',
      (a) => a.loadWidth(.i8, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '0fb64b08',
      (a) => a.loadWidth(.u8, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '420fb64c1108',
      (a) => a.loadWidth(.u8, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '440fb64b08',
      (a) => a.loadWidth(.u8, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '460fb64c1108',
      (a) => a.loadWidth(.u8, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '480fbf4b08',
      (a) => a.loadWidth(.i16, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '4a0fbf4c1108',
      (a) => a.loadWidth(.i16, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '4c0fbf4b08',
      (a) => a.loadWidth(.i16, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '4e0fbf4c1108',
      (a) => a.loadWidth(.i16, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '0fb74b08',
      (a) => a.loadWidth(.u16, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '420fb74c1108',
      (a) => a.loadWidth(.u16, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '440fb74b08',
      (a) => a.loadWidth(.u16, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '460fb74c1108',
      (a) => a.loadWidth(.u16, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '48634b08',
      (a) => a.loadWidth(.i32, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '4a634c1108',
      (a) => a.loadWidth(.i32, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '4c634b08',
      (a) => a.loadWidth(.i32, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '4e634c1108',
      (a) => a.loadWidth(.i32, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes('8b4b08', (a) => a.loadWidth(.u32, 1, const Memory(3, offset: 8)));
    _encodes(
      '428b4c1108',
      (a) => a.loadWidth(.u32, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '448b4b08',
      (a) => a.loadWidth(.u32, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '468b4c1108',
      (a) => a.loadWidth(.u32, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '488b4b08',
      (a) => a.loadWidth(.i64, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '4a8b4c1108',
      (a) => a.loadWidth(.i64, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '4c8b4b08',
      (a) => a.loadWidth(.i64, 9, const Memory(3, offset: 8)),
    );
    _encodes(
      '4e8b4c1108',
      (a) => a.loadWidth(.i64, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes('884b08', (a) => a.storeWidth(.u8, 1, const Memory(3, offset: 8)));
    _encodes(
      '4088707f',
      (a) => a.storeWidth(.u8, 6, const Memory(0, offset: 127)),
    );
    _encodes(
      '46884c1108',
      (a) => a.storeWidth(.u8, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '66894b08',
      (a) => a.storeWidth(.u16, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '6689707f',
      (a) => a.storeWidth(.u16, 6, const Memory(0, offset: 127)),
    );
    _encodes(
      '6646894c1108',
      (a) => a.storeWidth(.u16, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '894b08',
      (a) => a.storeWidth(.u32, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '89707f',
      (a) => a.storeWidth(.u32, 6, const Memory(0, offset: 127)),
    );
    _encodes(
      '46894c1108',
      (a) => a.storeWidth(.u32, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      '48894b08',
      (a) => a.storeWidth(.i64, 1, const Memory(3, offset: 8)),
    );
    _encodes(
      '4889707f',
      (a) => a.storeWidth(.i64, 6, const Memory(0, offset: 127)),
    );
    _encodes(
      '4e894c1108',
      (a) => a.storeWidth(.i64, 9, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      'f2420f104c1108',
      (a) => a.load(1, const Memory(1, offset: 8, index: 10), float: true),
    );
    _encodes(
      'f2420f114c1108',
      (a) => a.store(1, const Memory(1, offset: 8, index: 10), float: true),
    );
    _encodes(
      'f3420f104c1108f30f5ac9',
      (a) => a.loadWidth(.f32, 1, const Memory(1, offset: 8, index: 10)),
    );
    _encodes(
      'f2440f5af9f3460f117c1108',
      (a) => a.storeWidth(
        .f32,
        1,
        const Memory(1, offset: 8, index: 10),
        scratch: 15,
      ),
    );
    _encodes(
      'f2440f104c0d00',
      (a) => a.load(9, const Memory(5, index: 1), float: true),
    );
    _encodes(
      'f2440f114c0d00',
      (a) => a.store(9, const Memory(5, index: 1), float: true),
    );
    _encodes(
      'f3440f104c0d00f3450f5ac9',
      (a) => a.loadWidth(.f32, 9, const Memory(5, index: 1)),
    );
    _encodes(
      'f2450f5af9f3440f117c0d00',
      (a) => a.storeWidth(.f32, 9, const Memory(5, index: 1), scratch: 15),
    );
    _encodes('f20f58ca', (a) => a.floatBinary(.add, 1, 2));
    _encodes('f2440f58ca', (a) => a.floatBinary(.add, 9, 2));
    _encodes('f2410f58de', (a) => a.floatBinary(.add, 3, 14));
    _encodes('f20f5cca', (a) => a.floatBinary(.sub, 1, 2));
    _encodes('f2440f5cca', (a) => a.floatBinary(.sub, 9, 2));
    _encodes('f2410f5cde', (a) => a.floatBinary(.sub, 3, 14));
    _encodes('f20f59ca', (a) => a.floatBinary(.mul, 1, 2));
    _encodes('f2440f59ca', (a) => a.floatBinary(.mul, 9, 2));
    _encodes('f2410f59de', (a) => a.floatBinary(.mul, 3, 14));
    _encodes('f20f5eca', (a) => a.floatBinary(.div, 1, 2));
    _encodes('f2440f5eca', (a) => a.floatBinary(.div, 9, 2));
    _encodes('f2410f5ede', (a) => a.floatBinary(.div, 3, 14));
    _encodes('f20f51ca', (a) => a.floatBinary(.sqrt, 1, 2));
    _encodes('f2440f51ca', (a) => a.floatBinary(.sqrt, 9, 2));
    _encodes('f2410f51de', (a) => a.floatBinary(.sqrt, 3, 14));
    _encodes('660f28ca', (a) => a.fmov(1, 2));
    _encodes('660f57ca', (a) => a.fxor(1, 2));
    _encodes('660f2eca', (a) => a.fcmp(1, 2));
    _encodes('f2480f2aca', (a) => a.intToFloat(1, 2));
    _encodes('f2480f2cca', (a) => a.floatToInt(1, 2));
    _encodes('66480f6eca', (a) => a.bitsToFloat(1, 2));
    _encodes('66480f7ed1', (a) => a.floatToBits(1, 2));
    _encodes('66440f28ca', (a) => a.fmov(9, 2));
    _encodes('66440f57ca', (a) => a.fxor(9, 2));
    _encodes('66440f2eca', (a) => a.fcmp(9, 2));
    _encodes('f24c0f2aca', (a) => a.intToFloat(9, 2));
    _encodes('f24c0f2cca', (a) => a.floatToInt(9, 2));
    _encodes('664c0f6eca', (a) => a.bitsToFloat(9, 2));
    _encodes('66490f7ed1', (a) => a.floatToBits(9, 2));
    _encodes('66410f28de', (a) => a.fmov(3, 14));
    _encodes('66410f57de', (a) => a.fxor(3, 14));
    _encodes('66410f2ede', (a) => a.fcmp(3, 14));
    _encodes('f2490f2ade', (a) => a.intToFloat(3, 14));
    _encodes('f2490f2cde', (a) => a.floatToInt(3, 14));
    _encodes('66490f6ede', (a) => a.bitsToFloat(3, 14));
    _encodes('664c0f7ef3', (a) => a.floatToBits(3, 14));
    _encodes('400f92c6', (a) => a.setByte(6, .below));
    _encodes('400f93c6', (a) => a.setByte(6, .aboveOrEqual));
    _encodes('400f94c6', (a) => a.setByte(6, .equal));
    _encodes('400f95c6', (a) => a.setByte(6, .notEqual));
    _encodes('400f96c6', (a) => a.setByte(6, .belowOrEqual));
    _encodes('400f97c6', (a) => a.setByte(6, .above));
    _encodes('400f9ac6', (a) => a.setByte(6, .parity));
    _encodes('400f9bc6', (a) => a.setByte(6, .noParity));
    _encodes('400f9cc6', (a) => a.setByte(6, .less));
    _encodes('400f9dc6', (a) => a.setByte(6, .greaterOrEqual));
    _encodes('400f9ec6', (a) => a.setByte(6, .lessOrEqual));
    _encodes('400f9fc6', (a) => a.setByte(6, .greater));
    _encodes('410f93c3', (a) => a.setByte(11, .aboveOrEqual));
    _encodes('440fb6ce', (a) => a.extendByte(9, 6));
    _encodes('410fb6f1', (a) => a.extendByte(6, 9));
    _encodes('410fb6f3', (a) => a.extendByte(6, 11));
    _encodes('50', (a) => a.push(0));
    _encodes('58', (a) => a.pop(0));
    _encodes('4154', (a) => a.push(12));
    _encodes('415c', (a) => a.pop(12));
    _encodes('c9', (a) => a.leave());
    _encodes('c3', (a) => a.ret());
    _encodes('cc', (a) => a.breakpoint());
    _encodes('90', (a) => a.nop());
    _encodes('b900000000', (a) => a.constant(1, 0));
    _encodes('41b905000000', (a) => a.constant(9, 5));
    _encodes('b9ffffffff', (a) => a.constant(1, 4294967295));
    _encodes('41b900000080', (a) => a.constant(9, 2147483648));
    _encodes('48c7c1ffffffff', (a) => a.constant(1, -1));
    _encodes('49c7c100000080', (a) => a.constant(9, -2147483648));
    _encodes('48b90000000001000000', (a) => a.constant(1, 4294967296));
    _encodes('49b9ffffff7fffffffff', (a) => a.constant(9, -2147483649));
    _encodes('48baf0debc9a78563412', (a) => a.constant(2, 1311768467463790320));
    _encodes(
      '48ba0000000000000080',
      (a) => a.constant(2, -9223372036854775808),
    );
  });

  test('labels', () {
    final assembler = X64Assembler();
    final start = Label(), end = Label();
    assembler
      ..bind(start)
      ..jump(end)
      ..jumpIf(.less, start, holds: false)
      ..callLabel(end)
      ..bind(end);
    expect(assembler.finish(), [
      0xe9, 11, 0, 0, 0, //
      0x0f, 0x8d, 0xf5, 0xff, 0xff, 0xff, //
      0xe8, 0, 0, 0, 0,
    ]);
    expect(() => assembler.bind(end), throwsStateError);
  });

  test('symbols', () {
    final assembler = X64Assembler()
      ..call('f')
      ..address(9, 'g')
      ..loadSymbol(1, 'g')
      ..storeSymbol(1, 'g')
      ..cmpSymbol(1, 'g');
    expect(
      [for (final r in assembler.relocations) (r.offset, r.kind.name)],
      [
        (1, 'call32'),
        (8, 'relative32'),
        (15, 'relative32'),
        (22, 'relative32'),
        (29, 'relative32'),
      ],
    );
    expect(assembler.finish().take(8), [0xe8, 0, 0, 0, 0, 0x4c, 0x8d, 0x0d]);
  });

  test('what does not fit is rejected', () {
    final assembler = X64Assembler();
    expect(
      () => assembler.lea(1, const Memory(1, offset: 1 << 31)),
      throwsRangeError,
    );
    expect(
      () => assembler.lea(1, const Memory(1, index: 4)),
      throwsArgumentError,
    );
  });
}
