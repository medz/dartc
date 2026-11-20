import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

const zero = Constant.integer(0);
final uri = Uri.parse('memory:region-origin');
final map = FunctionTarget(uri, 'map', .integer, [.integer]),
    unmap = FunctionTarget(uri, 'unmap', .voidType, [.integer, .integer]);
final externals = [
  IrExternal(map, effects: const {.writesStorage}, memory: const .zeroed(0)),
  IrExternal(
    unmap,
    effects: const {.writesStorage},
    capturesArguments: false,
    memory: const .release(0, 1),
  ),
];

class Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType t) => ObjectLayout([]);
}

bool? truth(ProgramFlowFacts f, Value v) =>
    (f.valueOf(v).constant as ScalarConstant?)?.value as bool?;
void checkOrigin(
  String kind,
  FlowValue length,
  FlowValue offset,
  bool? expected,
) {
  final helper = FunctionTarget(uri, 'make', .integer, [
    .integer,
    .integer,
    .boolean,
    .integer,
  ]);
  final b = Block(helper.parameterTypes),
      good = Block([ValueType.integer]),
      bad = Block();
  final base = b.emit(DirectCall(map, [b.parameters[0]]));
  final badCheck = b.emit(Equals(base, zero));
  b.finish(Branch(badCheck, Jump(bad), Jump(good, [base])));
  if (kind == 'mixed' || kind == 'unchecked') {
    bad.finish(const Return(zero));
  } else {
    bad.finish(Throw(const Constant.string('no mapping')));
  }
  final live = good.parameters.single;
  final blocks = [b, good, bad];
  Value result = live;
  if (kind != 'unchecked' && kind != 'base') {
    result = good.emit(IntBinary(.add, live, b.parameters[1]));
  }
  if (kind == 'released') good.emit(DirectCall(unmap, [live, b.parameters[0]]));
  if (kind == 'released first page')
    good.emit(DirectCall(unmap, [live, const Constant.integer(4096)]));
  if (kind == 'retained') {
    result = good.emit(IntBinary(.bitAnd, result, zero));
  }
  if (kind == 'ordinary alternative') {
    final a = Block(), other = Block();
    blocks.addAll([a, other]);
    good.finish(Branch(b.parameters[2], Jump(a), Jump(other)));
    a.finish(Return(result));
    other.finish(Return(b.parameters[3]));
  } else if (kind == 'two regions' || kind == 'one released') {
    final q = good.emit(DirectCall(map, [b.parameters[0]]));
    final two = Block([ValueType.integer]), left = Block(), right = Block();
    blocks.addAll([two, left, right]);
    good.finish(Branch(good.emit(Equals(q, zero)), Jump(bad), Jump(two, [q])));
    two.finish(Branch(b.parameters[2], Jump(left), Jump(right)));
    if (kind == 'one released')
      left.emit(DirectCall(unmap, [live, b.parameters[0]]));
    left.finish(Return(result));
    right.finish(
      Return(
        right.emit(IntBinary(.add, two.parameters.single, b.parameters[1])),
      ),
    );
  } else {
    good.finish(Return(result));
  }
  final root = FunctionTarget(uri, 'inspect', .integer, [
    .integer,
    .integer,
    .boolean,
    .integer,
  ]);
  final entry = Block(root.parameterTypes), yes = Block(), no = Block();
  final ptr = entry.emit(DirectCall(helper, entry.parameters));
  final eq = entry.emit(Equals(ptr, zero)),
      ne = entry.emit(Equals(zero, ptr, negated: true));
  entry.finish(Branch(eq, Jump(yes), Jump(no)));
  yes.finish(const Return(Constant.integer(10)));
  no.finish(const Return(Constant.integer(20)));
  final graph = IrProgram([], [
    IrFunction(root, [entry, yes, no]),
    IrFunction(helper, blocks),
  ], externals: externals);
  final f = ProgramFlow(graph, [
    (
      target: root,
      arguments: [
        length,
        offset,
        FlowValue.unknown(.boolean),
        FlowValue.unknown(.integer),
      ],
    ),
  ], memoryLayout: Layout()).facts;
  final val = f.valueOf(ptr);
  print(
    '$kind length=${length.integers?.lower}..${length.integers?.upper} offset=${offset.integers?.lower}..${offset.integers?.upper} ==0=${truth(f, eq)} !=0=${truth(f, ne)} yes=${f.reachesBlock(yes)} no=${f.reachesBlock(no)} addr=${val.addresses.length} intAlternatives=${val.unknownTypes.length} retained=${val.references.addresses.length}',
  );
  if (kind == 'retained') {
    expect(val.addresses, isEmpty);
    expect(val.references.addresses, isNotEmpty);
    expect(truth(f, eq), isNot(false));
    expect(truth(f, ne), isNot(true));
    expect(f.reachesBlock(yes), isTrue);
    return;
  }
  expect(truth(f, eq), expected);
  expect(truth(f, ne), expected == null ? null : !expected);
  expect(f.reachesBlock(yes), expected != false);
  expect(f.reachesBlock(no), expected != true);
}

FlowValue integer(int v) => FlowValue.constant(Constant.integer(v));
void main() {
  final known = integer(65536);
  final uncertain = FlowValue.unknown(.integer);
  for (final (tag, extent, delta, result)
      in <(String, FlowValue, FlowValue, bool?)>[
        ('base', known, integer(0), false),
        ('interior', known, integer(24), false),
        ('last byte', known, integer(65535), false),
        (
          'bounded offsets',
          known,
          FlowValue.integerRange(FlowIntegerRange(1, 65535)),
          false,
        ),
        ('one past', known, integer(65536), null),
        ('negative', known, integer(-1), null),
        ('unknown extent', uncertain, integer(24), null),
        ('unknown delta', known, uncertain, null),
        (
          'range crosses end',
          known,
          FlowValue.integerRange(FlowIntegerRange(65535, 65536)),
          null,
        ),
        ('released', known, integer(24), null),
        ('released first page', known, integer(24), null),
        ('zero extent', integer(0), integer(0), null),
        ('negative extent', integer(-1), integer(24), null),
        ('mixed', known, integer(24), null),
        ('unchecked', known, integer(0), null),
        ('ordinary alternative', known, integer(24), null),
        ('two regions', known, integer(24), false),
        ('one released', known, integer(24), null),
        ('retained', known, integer(24), true),
        ('int max offset', known, integer(0x7fffffffffffffff), null),
        ('int min offset', known, integer(-0x8000000000000000), null),
      ]) {
    test(tag, () => checkOrigin(tag, extent, delta, result));
  }
}
