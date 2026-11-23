import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';

const integers = [0, 1, -1, 2, 7, -7, 63, 64, 100, _max, _min];
const _max = 0x7fffffffffffffff, _min = -0x8000000000000000;

const doubles = [
  0.0,
  -0.0,
  1.0,
  -1.0,
  5.5,
  -5.5,
  0.1,
  1e308,
  5e-324,
  double.infinity,
  double.negativeInfinity,
  double.nan,
];

/// A program whose `main` starts with what [build] adds.
HirModule body(
  HirTerminator Function(HirBlock block) build, [
  List<HirFunction> others = const [],
]) {
  final entry = HirBlock();
  entry.end(build(entry));
  final blocks = reversePostorder(
    entry,
    (block) => block.terminator!.edges.map((edge) => edge.target),
  );
  final main = HirFunction('main', const [])..define(blocks);
  return HirModule(main, [main, ...others]);
}

/// Dart's own answer, or null where it throws.
int? integerResult(HirIntOperator operator, int a, int b) => switch (operator) {
  .add => a + b,
  .subtract => a - b,
  .multiply => a * b,
  .divide => b == 0 ? null : a ~/ b,
  .modulo => b == 0 ? null : a % b,
  .and => a & b,
  .or => a | b,
  .xor => a ^ b,
  .shiftLeft => b < 0 ? null : a << b,
  .shiftRight => b < 0 ? null : a >> b,
  .shiftRightUnsigned => b < 0 ? null : a >>> b,
};

double doubleResult(HirFloatOperator operator, double a, double b) =>
    switch (operator) {
      .add => a + b,
      .subtract => a - b,
      .multiply => a * b,
      .divide => a / b,
      .modulo => a % b,
    };

bool relationResult(HirRelation relation, num a, num b) => switch (relation) {
  .equal => a == b,
  .notEqual => a != b,
  .less => a < b,
  .lessOrEqual => a <= b,
  .greater => a > b,
  .greaterOrEqual => a >= b,
};

/// Whether [found] is [expected], telling apart zeros and accepting any NaN.
HirValue sameDouble(HirBlock block, HirValue found, double expected) {
  if (expected.isNaN) return block.add(HirCompare(.notEqual, found, found));
  final value = block.add(HirConst(expected));
  final equal = block.add(HirCompare(.equal, found, value));
  if (expected != 0) return equal;
  final one = block.add(HirConst(1.0));
  final a = block.add(HirFloatBinary(.divide, one, found));
  final b = block.add(HirFloatBinary(.divide, one, value));
  final sign = block.add(HirCompare(.equal, a, b));
  return block.add(HirBoolBinary(.and, equal, sign));
}

/// Exits with the ninth Fibonacci number, found by a loop that calls `add`.
HirModule loopingCalls() {
  final sides = HirBlock([.integer, .integer]);
  final [left, right] = sides.parameters;
  sides.end(HirReturn(sides.add(HirIntBinary(.add, left, right))));
  final add = HirFunction('add', [.integer, .integer], .integer)
    ..define([sides]);
  final entry = HirBlock(), loop = HirBlock([.integer, .integer, .integer]);
  final done = HirBlock();
  final zero = entry.add(HirConst(0)), one = entry.add(HirConst(1));
  final nine = entry.add(HirConst(9));
  entry.end(HirJump(HirEdge(loop, [nine, zero, one])));
  final [count, a, b] = loop.parameters;
  // Both carried values change at once.
  final next = loop.add(HirCall(add, [a, b]));
  final rest = loop.add(HirIntBinary(.subtract, count, one));
  final more = loop.add(HirCompare(.greater, count, one));
  loop.end(HirBranch(more, HirEdge(loop, [rest, b, next]), HirEdge(done)));
  done.end(HirExit(b));
  final main = HirFunction('main', const [])..define([entry, loop, done]);
  return HirModule(main, [main, add]);
}
