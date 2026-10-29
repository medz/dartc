import '../../lib/src/runtime.dart' as rt;
import '../../lib/src/layout.dart' as abi;
import '../../lib/src/runtime/frames.dart';
import '../../lib/src/runtime/roots.dart' as roots;
import '../../lib/src/runtime/heap.dart' as heap;

const capacity = 2048;

class Leaf {
  int marker;
  Leaf(this.marker);
  int read() => marker;
  int call() => marker;
}

class ConstantLeaf {
  final int marker;
  final Object? wide;
  final String? text;
  final ConstantLeaf? child;
  final List<ConstantLeaf> refs;
  final List<Object?> tagged;
  const ConstantLeaf(
    this.marker,
    this.wide,
    this.text, [
    this.child,
    this.refs = const <ConstantLeaf>[],
    this.tagged = const <Object?>[],
  ]);

  String toString() => 'constant leaf';
}

class Wide {
  int marker = 200;
  int p0 = 0, p1 = 0, p2 = 0, p3 = 0, p4 = 0, p5 = 0, p6 = 0;
  int p7 = 0, p8 = 0, p9 = 0, p10 = 0, p11 = 0, p12 = 0, p13 = 0;
  int p14 = 0, p15 = 0, p16 = 0, p17 = 0, p18 = 0, p19 = 0, p20 = 0;
  int p21 = 0, p22 = 0, p23 = 0, p24 = 0, p25 = 0, p26 = 0, p27 = 0;
  int p28 = 0, p29 = 0, p30 = 0, p31 = 0, p32 = 0, p33 = 0, p34 = 0;
  int p35 = 0, p36 = 0, p37 = 0, p38 = 0, p39 = 0, p40 = 0, p41 = 0;
  int p42 = 0, p43 = 0, p44 = 0, p45 = 0, p46 = 0, p47 = 0, p48 = 0;
  int p49 = 0, p50 = 0, p51 = 0, p52 = 0, p53 = 0, p54 = 0, p55 = 0;
  int p56 = 0, p57 = 0, p58 = 0, p59 = 0, p60 = 0, p61 = 0;
  Leaf p62;
  Leaf tail;
  Object? taggedTail;
  int p63 = 0, p64 = 0, p65 = 0, p66 = 0, p67 = 0, p68 = 0, p69 = 0;
  int p70 = 0, p71 = 0, p72 = 0, p73 = 0, p74 = 0, p75 = 0, p76 = 0;
  int p77 = 0, p78 = 0, p79 = 0, p80 = 0, p81 = 0, p82 = 0, p83 = 0;
  int p84 = 0, p85 = 0, p86 = 0, p87 = 0, p88 = 0, p89 = 0, p90 = 0;
  int p91 = 0, p92 = 0, p93 = 0, p94 = 0, p95 = 0, p96 = 0, p97 = 0;
  int p98 = 0, p99 = 0, p100 = 0, p101 = 0, p102 = 0, p103 = 0, p104 = 0;
  int p105 = 0, p106 = 0, p107 = 0, p108 = 0, p109 = 0, p110 = 0, p111 = 0;
  int p112 = 0, p113 = 0, p114 = 0, p115 = 0, p116 = 0, p117 = 0, p118 = 0;
  int p119 = 0, p120 = 0, p121 = 0, p122 = 0, p123 = 0, p124 = 0, p125 = 0;
  Leaf third;
  Wide(this.tail, this.taggedTail, this.p62, this.third);
}

abstract class WideOwnFields {
  factory WideOwnFields(
    Leaf tail,
    Object? tagged,
    Leaf edge,
    Leaf third,
    Leaf own,
    Object? ownTagged,
  ) = DerivedWide;
  Leaf get own;
  Object? get ownTagged;
}

class DerivedWide(
  super.tail,
  super.tagged,
  super.p62,
  super.third,
  var own,
  var ownTagged,
) extends Wide implements WideOwnFields {
  late Leaf delayed = Leaf(207);
}

class Watch {
  int queue;
  bool formatting;
  int edges;
  int input = 0;
  Watch(this.queue, [this.formatting = false, this.edges = 0]);

  String toString() {
    var count = snapshot(queue);
    if (formatting) {
      check(formatterEdges(queue, count, edges, input));
      check(hasStringRoot(queue, count, 44, 32, 2));
    } else {
      check(findMarker(queue, count, 160) != 0);
    }
    return 'watched';
  }
}

Leaf globalLeaf = .new(180);
Object? globalBox = 9223372036854775807;
const cached = <Object?>[
  <int>[181],
  'cache',
];

void check(bool condition) {
  if (!condition) {
    print('roots mismatch');
    rt.rtHostExit(72);
  }
}

int findMarker(int queue, int count, int marker) {
  var i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(queue + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor + abi.descriptorKindOffset) ==
            abi.descriptorClass &&
        rt.nativeLoad64(descriptor + abi.descriptorFieldsOffset) > 0 &&
        rt.nativeLoad64(object + abi.objectHeaderBytes) == marker) {
      return object;
    }
    i++;
  }
  return 0;
}

bool contains(int queue, int count, int object) {
  var i = 0;
  while (i < count) {
    if (rt.nativeLoad64(queue + i * 8) == object) return true;
    i++;
  }
  return false;
}

bool hasStringRoot(int queue, int count, int first, int second, int length) {
  var i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(queue + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor + abi.descriptorKindOffset) ==
            abi.descriptorString &&
        rt.rtStringLength(object) == length &&
        rt.rtStringCodeUnit(object, 0) == first &&
        (length == 1 || rt.rtStringCodeUnit(object, 1) == second)) {
      return true;
    }
    i++;
  }
  return false;
}

@pragma('dartc:no-gc')
int copyTrace(int buffer, int output) {
  final count = rt.nativeLoad64(buffer + 8);
  if (count > capacity) roots.rtRootFailure();
  final data = rt.nativeLoad64(buffer);
  for (var i = 0; i < count; i++)
    rt.nativeStore64(output + i * 8, rt.nativeLoad64(data + i * 8));
  roots.rtTraceBufferFree(buffer);
  return count;
}

@pragma('dartc:no-gc')
int traceRoots(int frame, int output) {
  final buffer = roots.rtTraceBufferNew();
  roots.rtTraceRoots(frame, buffer);
  return copyTrace(buffer, output);
}

@pragma('dartc:no-gc')
int traceObject(int value, int output) {
  final buffer = roots.rtTraceBufferNew();
  roots.rtTraceObject(value, buffer);
  return copyTrace(buffer, output);
}

int snapshot(int queue) {
  return traceRoots(rt.nativeFramePointer(), queue);
}

int capture(Object? value, int marker, int queue) {
  var count = traceRoots(rt.nativeFramePointer(), queue);
  var object = findMarker(queue, count, marker);
  check(object != 0);
  return object;
}

int captureList(Object? value, int length, int queue) {
  var count = traceRoots(rt.nativeFramePointer(), queue);
  var i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(queue + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor + abi.descriptorKindOffset) ==
            abi.descriptorList &&
        rt.rtListLength(object) == length) {
      return object;
    }
    i++;
  }
  check(false);
  return 0;
}

int listElements(int object, int queue) {
  check(traceObject(object, queue) == 1);
  var backing = rt.nativeLoad64(queue);
  return traceObject(backing, queue);
}

bool formatterEdges(int queue, int count, int edges, int input) {
  var active = false;
  var parts = false;
  var i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(queue + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor + abi.descriptorKindOffset) ==
            abi.descriptorList &&
        rt.rtListLength(object) != 0) {
      var children = listElements(object, edges);
      if (contains(edges, children, input)) active = true;
      if (hasStringRoot(edges, children, 91, 0, 1)) parts = true;
    }
    i++;
  }
  return active && parts;
}

int many(
  Object? a,
  Object? b,
  Object? c,
  Object? d,
  Object? e,
  Object? f,
  Object? g,
  Object? h,
  Object? ninth,
  int queue,
) {
  return snapshot(queue);
}

int recurse(int depth, int queue) {
  var keep = Leaf(140 + depth);
  var count = 0;
  if (depth == 0)
    count = snapshot(queue);
  else
    count = recurse(depth - 1, queue);
  check(keep.marker == 140 + depth);
  return count;
}

void runtimeOwnership(int queue, int edges) {
  var mark = roots.rtRootMark();
  var first = capture(Leaf(401), 401, queue);
  check(!contains(queue, snapshot(queue), first));
  roots.rtRootPush(first, abi.storageRef);
  check(contains(queue, snapshot(queue), first));
  var nested = roots.rtRootMark();
  var second = capture(Leaf(402), 402, queue);
  roots.rtRootPush(second, abi.storageTagged);
  var persistent = roots.rtGlobalRootNew(second, abi.storageRef);
  roots.rtRootRestore(nested);
  check(contains(queue, snapshot(queue), second));
  roots.rtRootRestore(mark);
  var count = snapshot(queue);
  check(!contains(queue, count, first) && contains(queue, count, second));
  roots.rtGlobalRootSet(persistent, first);
  check(roots.rtGlobalRootValue(persistent) == first);
  count = snapshot(queue);
  check(contains(queue, count, first) && !contains(queue, count, second));
  roots.rtGlobalRootSet(persistent, 0);
  check(!contains(queue, snapshot(queue), first));

  roots.rtRootPush(0, abi.storageRef);
  roots.rtRootPush(0, abi.storageTagged);
  roots.rtRootPush(abi.valueFalse, abi.storageTagged);
  roots.rtRootPush(abi.valueTrue, abi.storageTagged);
  roots.rtRootPush(rt.rtBoxInt(-7), abi.storageTagged);
  check(roots.rtRootMark() == mark);
  var box = rt.rtBoxInt(9223372036854775807);
  roots.rtRootPush(box, abi.storageTagged);
  check(contains(queue, snapshot(queue), box));
  roots.rtRootRestore(mark);
  check(!contains(queue, snapshot(queue), box));

  roots.rtRootPush(second, abi.storageRef);
  var i = 1;
  while (i < 1100) {
    roots.rtRootPush(first, abi.storageTagged);
    i++;
  }
  check(roots.rtRootMark() == mark + 1100);
  count = snapshot(queue);
  check(contains(queue, count, first) && contains(queue, count, second));
  roots.rtRootRestore(mark);
  count = snapshot(queue);
  check(!contains(queue, count, first) && !contains(queue, count, second));
  var stable = roots.rtGlobalRootNew(first, abi.storageTagged);
  i = 0;
  while (i < 1100) {
    roots.rtGlobalRootNew(0, abi.storageRef);
    i++;
  }
  check(roots.rtGlobalRootValue(stable) == first);
  roots.rtGlobalRootSet(persistent, second);
  count = snapshot(queue);
  check(contains(queue, count, first) && contains(queue, count, second));
  roots.rtGlobalRootSet(stable, 0);
  roots.rtGlobalRootSet(persistent, 0);
  count = snapshot(queue);
  check(!contains(queue, count, first) && !contains(queue, count, second));

  var watched = Watch(queue, true, edges);
  var rendering = <Object>[watched, 9223372036854775807, 'tail', true, false];
  watched.input = captureList(rendering, 5, queue);
  check(
    rendering.toString() == '[watched, 9223372036854775807, tail, true, false]',
  );
  check(roots.rtRootMark() == mark);
  Object fallback = Leaf(403);
  check(fallback.toString() == "Instance of 'Leaf'");
  check(roots.rtRootMark() == mark);
  var cyclic = <Object>[];
  cyclic.add(cyclic);
  check(cyclic.toString() == '[[...]]');
  check(roots.rtRootMark() == mark);
}

void constantObjectRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  const child = ConstantLeaf(501, 9223372036854775807, 'const🙂');
  const parent = ConstantLeaf(
    502,
    -9223372036854775808,
    null,
    child,
    <ConstantLeaf>[child],
    <Object?>[child, null],
  );
  var parentAddress = capture(parent, 502, queue);
  check(roots.rtRootMark() == mark);
  var count = traceObject(parentAddress, edges);
  var childAddress = findMarker(edges, count, 501);
  var refs = 0;
  var tagged = 0;
  var wide = 0;
  var i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(edges + i * 8);
    var kind = rt.nativeLoad64(
      rt.rtObjectDescriptor(object) + abi.descriptorKindOffset,
    );
    if (kind == abi.descriptorList) {
      if (rt.rtListLength(object) == 1) refs = object;
      if (rt.rtListLength(object) == 2) tagged = object;
    }
    if (kind == abi.descriptorIntBox) wide = object;
    i++;
  }
  check(
    count == 4 && childAddress != 0 && refs != 0 && tagged != 0 && wide != 0,
  );
  check(rt.nativeLoad64(wide + abi.objectHeaderBytes) == -9223372036854775808);
  check(listElements(refs, edges) == 1 && contains(edges, 1, childAddress));
  check(listElements(tagged, edges) == 1 && contains(edges, 1, childAddress));
  count = traceObject(childAddress, edges);
  check(count == 4 && hasStringRoot(edges, count, 99, 111, 7));
  wide = 0;
  i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(edges + i * 8);
    if (rt.nativeLoad64(
          rt.rtObjectDescriptor(object) + abi.descriptorKindOffset,
        ) ==
        abi.descriptorIntBox)
      wide = object;
    i++;
  }
  check(
    wide != 0 &&
        rt.nativeLoad64(wide + abi.objectHeaderBytes) == 9223372036854775807,
  );
  check(capture(parent, 502, queue) == parentAddress);
  count = snapshot(queue);
  check(
    contains(queue, count, parentAddress) &&
        contains(queue, count, childAddress),
  );
  Object value = parent;
  check(value.toString() == 'constant leaf');
  check(roots.rtRootMark() == mark);
}

@pragma('dartc:no-gc')
int noGcScope(int raw, int queue) {
  var mark = roots.rtRootMark();
  var i = 0;
  while (i < 1100) {
    roots.rtRootPush(raw, abi.storageRef);
    i++;
  }
  var count = traceRoots(rt.nativeFramePointer(), queue);
  roots.rtRootRestore(mark);
  return count;
}

void noGcRoots(int queue) {
  var raw = capture(Leaf(601), 601, queue);
  var mark = roots.rtRootMark();
  var count = noGcScope(raw, queue);
  check(contains(queue, count, raw));
  check(roots.rtRootMark() == mark);
  check(!contains(queue, snapshot(queue), raw));
}

void sharedFilledEdges(int list, int value, int edges) {
  var count = listElements(list, edges);
  check(count == 3);
  var i = 0;
  while (i < count) {
    check(rt.nativeLoad64(edges + i * 8) == value);
    i++;
  }
}

void builderRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  var words = <int>[701];
  var wordType = rt.nativeLoad64(
    captureList(words, 1, queue) + abi.listTypeOffset,
  );
  var intType = rt.rtTypeArgument(wordType);
  var objects = <Object?>[];
  var list = captureList(objects, 0, queue);
  var objectType = rt.nativeLoad64(list + abi.listTypeOffset);
  rt.rtListAdd(list, 9223372036854775807, intType);
  check(objects.length == 1 && roots.rtRootMark() == mark);
  var full = rt.nativeLoad64(list + abi.listCapacityOffset);
  var i = 1;
  while (i < full) {
    rt.rtListAdd(list, i, intType);
    i++;
  }
  rt.rtListAdd(list, 9223372036854775807, intType);
  check(objects.length == full + 1 && roots.rtRootMark() == mark);
  var count = listElements(list, edges);
  check(count == 2);
  i = 0;
  while (i < count) {
    var boxed = rt.nativeLoad64(edges + i * 8);
    check(
      rt.nativeLoad64(
                rt.rtObjectDescriptor(boxed) + abi.descriptorKindOffset,
              ) ==
              abi.descriptorIntBox &&
          rt.nativeLoad64(boxed + abi.objectHeaderBytes) == 9223372036854775807,
    );
    i++;
  }
  var wide = rt.nativeLoad64(edges);
  var refs = <Leaf>[.new(702)];
  var refType = rt.nativeLoad64(
    captureList(refs, 1, queue) + abi.listTypeOffset,
  );
  var child = capture(refs[0], 702, queue);
  sharedFilledEdges(rt.rtListFilled(3, child, 1, refType), child, edges);
  check(roots.rtRootMark() == mark);
  sharedFilledEdges(rt.rtListFilled(3, wide, 1, objectType), wide, edges);
  check(roots.rtRootMark() == mark);
  var rawWords = rt.rtListFilled(3, child, 1, wordType);
  check(listElements(rawWords, edges) == 0 && roots.rtRootMark() == mark);
  check(refs[0].marker == 702 && objects[0] == 9223372036854775807);
}

List<int Function()> closureGraph() {
  final fixed = Leaf(802);
  Object? shared = Leaf(801);
  var number = 0;
  int read() => fixed.marker + (shared as Leaf).marker + number;
  int next() {
    shared = Leaf(803);
    return ++number;
  }

  return [read, next];
}

bool keepPatternClosure(List<int Function()> list, int Function() read) {
  list.add(read);
  return true;
}

List<int Function()> ifCaseGraph() {
  var result = <int Function()>[];
  if (Leaf(807) case var value
      when keepPatternClosure(result, () => value.marker)) {
    value = Leaf(808);
    result.add(() => value.marker);
  }
  return result;
}

class PatternRoot {
  int reads = 0;
  Leaf get child {
    reads++;
    return Leaf(811);
  }
}

bool objectPatternGuard(int queue) {
  check(findMarker(queue, snapshot(queue), 811) != 0);
  return false;
}

bool listPatternGuard(List<Leaf> source, int queue, int edges) {
  source.clear();
  var count = snapshot(queue);
  for (var i = 0; i < count; i++) {
    var object = rt.nativeLoad64(queue + i * 8);
    if (rt.nativeLoad64(
              rt.rtObjectDescriptor(object) + abi.descriptorKindOffset,
            ) ==
            abi.descriptorList &&
        rt.rtListLength(object) == 1) {
      var children = listElements(object, edges);
      if (findMarker(edges, children, 816) != 0) return false;
    }
  }
  check(false);
  return false;
}

void listPatternRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  var source = <Leaf>[Leaf(815), Leaf(816)];
  var selected = switch (source) {
    [_, ...var rest] when listPatternGuard(source, queue, edges) => rest,
    [_, ...var rest] => rest,
    _ => <Leaf>[],
  };
  var list = captureList(selected, 1, queue);
  check(listElements(list, edges) == 1);
  check(findMarker(edges, 1, 816) != 0 && selected[0].marker == 816);
  var tagged = <Object?>[null, Leaf(817), 9223372036854775807, true].sublist(1);
  list = captureList(tagged, 3, queue);
  check(listElements(list, edges) == 2);
  check(findMarker(edges, 2, 817) != 0);
  check(tagged[1] == 9223372036854775807);
  var words = <int>[1, 2, 3, 4].sublist(0);
  list = captureList(words, 4, queue);
  check(listElements(list, edges) == 0 && words[3] == 4);
  check(roots.rtRootMark() == mark);
}

class DestructureRoot {
  int queue;
  DestructureRoot(this.queue);
  Leaf get first => Leaf(818);
  Leaf get second {
    check(findMarker(queue, snapshot(queue), 818) != 0);
    return Leaf(819);
  }
}

void destructuringRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  final DestructureRoot(:first, :second) = DestructureRoot(queue);
  check(first.marker == 818 && second.marker == 819);
  var [head, ...tail] = <Leaf>[Leaf(820), Leaf(821)];
  var reads = <int Function()>[() => head.marker, () => tail[0].marker];
  [head, ...tail] = <Leaf>[Leaf(822), Leaf(823)];
  var list = captureList(reads, 2, queue);
  check(listElements(list, edges) == 2);
  var headRead = rt.nativeLoad64(edges);
  var tailRead = rt.nativeLoad64(edges + 8);
  check(traceObject(headRead, edges) == 1);
  check(traceObject(rt.nativeLoad64(edges), edges) == 1);
  check(findMarker(edges, 1, 822) != 0);
  check(traceObject(tailRead, edges) == 1);
  check(traceObject(rt.nativeLoad64(edges), edges) == 1);
  check(listElements(rt.nativeLoad64(edges), edges) == 1);
  check(findMarker(edges, 1, 823) != 0);
  check(reads[0]() == 822 && reads[1]() == 823);
  check(roots.rtRootMark() == mark);
}

void switchStatementRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  var functions = <int Function()>[];
  Object value = Leaf(824);
  switch (value) {
    case Leaf leaf when keepPatternClosure(functions, () => leaf.marker):
    case [Leaf leaf]:
      leaf = Leaf(825);
      functions.add(() => leaf.marker);
  }
  var list = captureList(functions, 2, queue);
  check(listElements(list, edges) == 2);
  var guard = rt.nativeLoad64(edges);
  var body = rt.nativeLoad64(edges + 8);
  check(traceObject(guard, edges) == 1);
  check(findMarker(edges, 1, 824) != 0);
  check(traceObject(body, edges) == 1);
  var cell = rt.nativeLoad64(edges);
  check(rt.nativeLoad64(rt.rtObjectDescriptor(cell)) == abi.captureCellClassId);
  check(traceObject(cell, edges) == 1);
  check(findMarker(edges, 1, 825) != 0);
  check(functions[0]() == 824 && functions[1]() == 825);
  check(roots.rtRootMark() == mark);
}

void closureRoots(int queue, int edges) {
  final argumentCallbacks =
      <
        void Function(
          int, {
          required Object? first,
          required Object? second,
          required Object? third,
          required Object? fourth,
          required Object? fifth,
          required Object? sixth,
          required Object? seventh,
          required Object? eighth,
          required Object? ninth,
        })
      >[namedArgumentRoots, ConstructorArgumentRoots.new];
  for (final arguments in argumentCallbacks)
    arguments(
      queue,
      ninth: Leaf(849),
      first: Leaf(841),
      seventh: Leaf(847),
      third: Leaf(843),
      fifth: Leaf(845),
      second: Leaf(842),
      eighth: Leaf(848),
      fourth: Leaf(844),
      sixth: Leaf(846),
    );
  var generic = namedTypeRoot<Leaf>(Leaf(850));
  var callbacksWithNames = <Leaf Function({required Leaf value})>[generic];
  var namedList = captureList(callbacksWithNames, 1, queue);
  check(listElements(namedList, edges) == 1);
  var namedCallback = rt.nativeLoad64(edges);
  var namedType = rt.rtFunctionType(namedCallback);
  check(traceObject(namedCallback, edges) == 3);
  check(contains(edges, 3, namedType));
  check(findMarker(edges, 3, 850) != 0);
  check(generic(value: Leaf(851)).marker == 851);
  var owner = PatternRoot();
  var objectPatterns = <int Function()>[
    switch (owner) {
      PatternRoot(child: Leaf(marker: 0)) => () => 0,
      PatternRoot(child: _) when objectPatternGuard(queue) => () => 0,
      PatternRoot(child: Leaf(read: var read)) => read,
    },
  ];
  check(owner.reads == 1);
  var objectPatternList = captureList(objectPatterns, 1, queue);
  check(listElements(objectPatternList, edges) == 1);
  check(traceObject(rt.nativeLoad64(edges), edges) == 1);
  check(findMarker(edges, 1, 811) != 0);
  check(objectPatterns[0]() == 811);
  var cases = ifCaseGraph();
  var caseList = captureList(cases, 2, queue);
  check(listElements(caseList, edges) == 2);
  var guard = rt.nativeLoad64(edges);
  var body = rt.nativeLoad64(edges + 8);
  check(traceObject(guard, edges) == 1);
  var cell = rt.nativeLoad64(edges);
  check(rt.nativeLoad64(rt.rtObjectDescriptor(cell)) == abi.captureCellClassId);
  check(traceObject(body, edges) == 1);
  check(rt.nativeLoad64(edges) == cell);
  check(traceObject(cell, edges) == 1);
  check(findMarker(edges, 1, 808) != 0);
  check(cases[0]() == 808 && cases[1]() == 808);
  var patterns = <int Function()>[
    switch (Leaf(806)) {
      Leaf value => () => value.marker,
    },
  ];
  var patternList = captureList(patterns, 1, queue);
  check(listElements(patternList, edges) == 1);
  var pattern = rt.nativeLoad64(edges);
  check(traceObject(pattern, edges) == 1);
  check(findMarker(edges, 1, 806) != 0);
  check(patterns[0]() == 806);
  var callables = <int Function()>[Leaf(805)];
  var callableList = captureList(callables, 1, queue);
  check(listElements(callableList, edges) == 1);
  var callable = rt.nativeLoad64(edges);
  check(traceObject(callable, edges) == 1);
  check(findMarker(edges, 1, 805) != 0);
  check(callables[0]() == 805);
  var methods = <int Function()>[Leaf(804).read];
  var methodList = captureList(methods, 1, queue);
  check(listElements(methodList, edges) == 1);
  var method = rt.nativeLoad64(edges);
  var descriptor = rt.rtObjectDescriptor(method);
  check(rt.nativeLoad64(descriptor) == abi.boundMethodClassId);
  check(traceObject(method, edges) == 1);
  check(findMarker(edges, 1, 804) != 0);
  check(methods[0]() == 804);
  var callbacks = closureGraph();
  var list = captureList(callbacks, 2, queue);
  check(listElements(list, edges) == 2);
  var read = rt.nativeLoad64(edges);
  var next = rt.nativeLoad64(edges + 8);
  check(traceObject(read, edges) == 3);
  check(findMarker(edges, 3, 802) != 0);
  var shared = 0;
  var cells = 0;
  for (var i = 0; i < 3; i++) {
    var object = rt.nativeLoad64(edges + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor) == abi.captureCellClassId) {
      cells++;
      var count = traceObject(object, queue);
      if (count == 1) {
        check(findMarker(queue, count, 801) != 0);
        shared = object;
      } else {
        check(count == 0);
      }
    }
  }
  check(cells == 2 && shared != 0);
  check(traceObject(next, edges) == 2);
  check(contains(edges, 2, shared));
  check(callbacks[0]() == 1603 && callbacks[1]() == 1);
  check(traceObject(shared, edges) == 1);
  check(findMarker(edges, 1, 803) != 0);
  check(callbacks[0]() == 1606);
}

T Function({required T value}) namedTypeRoot<T>(Leaf leaf) =>
    ({required T value}) {
      check(leaf.marker == 850);
      return value;
    };

void namedArgumentRoots(
  int queue, {
  required Object? first,
  required Object? second,
  required Object? third,
  required Object? fourth,
  required Object? fifth,
  required Object? sixth,
  required Object? seventh,
  required Object? eighth,
  required Object? ninth,
}) {
  // No parameter is read here: their caller's borrowed vector owns these roots.
  checkNamedArgumentRoots(queue);
}

class ConstructorArgumentRoots {
  final int marker = 852;
  ConstructorArgumentRoots(
    int queue, {
    required Object? first,
    required Object? second,
    required Object? third,
    required Object? fourth,
    required Object? fifth,
    required Object? sixth,
    required Object? seventh,
    required Object? eighth,
    required Object? ninth,
  }) {
    checkNamedArgumentRoots(queue);
    check(findMarker(queue, snapshot(queue), 852) != 0);
  }
}

void checkNamedArgumentRoots(int queue) {
  final count = snapshot(queue);
  for (var marker = 841; marker <= 849; marker++)
    check(findMarker(queue, count, marker) != 0);
}

int heapType(int source, [int child = -1]) {
  var mark = roots.rtRootMark();
  roots.rtRootPush(source, abi.storageRef);
  if (child >= 0) roots.rtRootPush(child, abi.storageRef);
  var result = heap.rtAlloc(abi.typeRefBytes);
  rt.nativeStore64(result, rt.rtObjectDescriptor(source));
  rt.nativeStore64(result + abi.objectFlagsOffset, 0);
  rt.nativeStore64(
    result + abi.typeKindOffset,
    rt.nativeLoad64(source + abi.typeKindOffset),
  );
  rt.nativeStore64(
    result + abi.typeArgumentOffset,
    child < 0 ? 0 : child - result,
  );
  var descriptor = rt.nativeLoad64(source + abi.typeClassOffset);
  rt.nativeStore64(
    result + abi.typeClassOffset,
    descriptor == 0 ? 0 : source + descriptor - result,
  );
  rt.nativeStore64(
    result + abi.typeValueRepOffset,
    rt.nativeLoad64(source + abi.typeValueRepOffset),
  );
  roots.rtRootRestore(mark);
  return result;
}

int heapFunctionType(int source, int resultType, int parameterType) {
  var mark = roots.rtRootMark();
  roots.rtRootPush(source, abi.storageRef);
  roots.rtRootPush(resultType, abi.storageRef);
  roots.rtRootPush(parameterType, abi.storageRef);
  var result = heap.rtAlloc(
    abi.typeRefBytes + abi.functionSignatureParametersOffset + 8,
  );
  rt.nativeStore64(result, rt.rtObjectDescriptor(source));
  rt.nativeStore64(result + abi.objectFlagsOffset, 0);
  rt.nativeStore64(result + abi.typeKindOffset, abi.typeKindFunction);
  rt.nativeStore64(result + abi.typeArgumentOffset, abi.typeRefBytes);
  rt.nativeStore64(result + abi.typeClassOffset, 0);
  rt.nativeStore64(result + abi.typeValueRepOffset, abi.storageRef);
  var signature = result + abi.typeRefBytes;
  rt.nativeStore64(
    signature + abi.functionSignatureResultOffset,
    resultType - signature,
  );
  rt.nativeStore64(signature + abi.functionSignatureRequiredOffset, 1);
  rt.nativeStore64(signature + abi.functionSignatureCountOffset, 1);
  rt.nativeStore64(signature + abi.functionSignaturePositionalOffset, 1);
  var parameter = signature + abi.functionSignatureParametersOffset;
  rt.nativeStore64(parameter, parameterType - parameter);
  roots.rtRootRestore(mark);
  return result;
}

List<int> Function(List<int>) typeGraphCallback(Leaf leaf) =>
    (List<int> input) => <int>[input[0] + leaf.marker];

void typeGraphRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  var words = <int>[831];
  var list = captureList(words, 1, queue);
  var staticListType = rt.nativeLoad64(list + abi.listTypeOffset);
  check(traceObject(staticListType, 0) == 0);
  var intType = heapType(rt.rtTypeArgument(staticListType));
  roots.rtRootPush(intType, abi.storageRef);
  var listType = heapType(staticListType, intType);
  rt.nativeStore64(list + abi.listTypeOffset, listType);
  check(traceObject(list, edges) == 2);
  check(contains(edges, 2, listType));
  check(traceObject(listType, edges) == 1);
  check(rt.nativeLoad64(edges) == intType);
  check(traceObject(intType, 0) == 0);
  Object value = words;
  check(value is List<int> && value is! List<String>);
  words.add(832);
  check(words.removeLast() == 832 && words[0] == 831);
  var copied = words.sublist(0);
  check(copied[0] == 831);

  var nullable = <int?>[null, 833];
  var nullableList = captureList(nullable, 2, queue);
  var nullableListType = rt.nativeLoad64(nullableList + abi.listTypeOffset);
  var nullableType = heapType(rt.rtTypeArgument(nullableListType), intType);
  roots.rtRootPush(nullableType, abi.storageRef);
  var nullableCopy = heapType(nullableListType, nullableType);
  rt.nativeStore64(nullableList + abi.listTypeOffset, nullableCopy);
  check(traceObject(nullableCopy, edges) == 1);
  check(rt.nativeLoad64(edges) == nullableType);
  check(traceObject(nullableType, edges) == 1);
  check(rt.nativeLoad64(edges) == intType);
  value = nullable;
  check(value is List<int?> && value is! List<int>);
  check(nullable[0] == null && nullable[1] == 833);

  var read = typeGraphCallback(Leaf(834));
  var callbacks = <List<int> Function(List<int>)>[read, read, read];
  var functions = captureList(callbacks, 3, queue);
  check(listElements(functions, edges) == 3);
  var callback = rt.nativeLoad64(edges);
  var type = heapFunctionType(rt.rtFunctionType(callback), listType, listType);
  rt.nativeStore64(callback + abi.functionTypeOffset, type);
  check(traceObject(callback, edges) == 2);
  check(contains(edges, 2, type) && findMarker(edges, 2, 834) != 0);
  check(traceObject(type, edges) == 2);
  check(rt.nativeLoad64(edges) == listType);
  check(rt.nativeLoad64(edges + 8) == listType);
  value = callbacks[0];
  check(value is List<int> Function(List<int>));
  check(value is! List<String> Function(List<int>));
  check(callbacks[0](words)[0] == 1665);
  check(roots.rtRootMark() == mark + 2);
  roots.rtRootRestore(mark);
  check(roots.rtRootMark() == mark);
}

List<T> genericRootList<T>(T value) => [value];
List<List<T>> genericRootNested<T>(T value) => [genericRootList<T>(value)];
List<List<T> Function(List<T>)> genericRootCallbacks<T>(
  List<T> Function(List<T>) callback,
) => [callback, callback, callback];
List<T> Function(List<T>) genericRootCallback<T>(T retained) =>
    (List<T> values) => [retained, values[0]];
bool Function(Object?) genericRootTypeTest<T>() =>
    (value) => value is T;
bool Function(Object?) genericNestedRootTypeTest<T>() =>
    genericRootTypeTest<List<T>>();

void genericTypeRoots(int queue, int edges) {
  var mark = roots.rtRootMark();
  var nested = genericRootNested<Leaf>(Leaf(841));
  var outer = captureList(nested, 1, queue);
  var outerType = rt.nativeLoad64(outer + abi.listTypeOffset);
  check(
    (rt.nativeLoad64(outerType + abi.objectFlagsOffset) &
            (abi.objectStaticRelative | abi.objectTypeTemplate)) ==
        0,
  );
  check(traceObject(outer, edges) == 2);
  check(contains(edges, 2, outerType));
  check(traceObject(outerType, edges) == 1);
  var innerType = rt.nativeLoad64(edges);
  check(rt.nativeLoad64(innerType + abi.typeKindOffset) == abi.typeKindList);
  check(traceObject(innerType, edges) == 0);
  Object value = nested;
  check(value is List<List<Leaf>> && value is! List<List<int>>);
  check(nested[0][0].marker == 841);

  var callbacks = genericRootCallbacks<Leaf>(
    genericRootCallback<Leaf>(Leaf(842)),
  );
  var list = captureList(callbacks, 3, queue);
  var listType = rt.nativeLoad64(list + abi.listTypeOffset);
  check(traceObject(listType, edges) == 1);
  var functionType = rt.nativeLoad64(edges);
  check(traceObject(functionType, edges) == 2);
  var resultType = rt.nativeLoad64(edges);
  var parameterType = rt.nativeLoad64(edges + 8);
  check(traceObject(resultType, edges) == 0);
  check(traceObject(parameterType, edges) == 0);
  check(traceObject(list, edges) == 2);
  var backing = rt.nativeLoad64(list + abi.listBackingOffset);
  check(contains(edges, 2, listType) && contains(edges, 2, backing));
  check(traceObject(backing, edges) == 3);
  var callback = rt.nativeLoad64(edges);
  check(traceObject(callback, edges) == 3);
  check(contains(edges, 3, rt.rtFunctionType(callback)));
  check(findMarker(edges, 3, 842) != 0);
  var environment = rt.nativeLoad64(callback + abi.functionInstanceBytes);
  check(contains(edges, 3, environment));
  check(traceObject(environment, edges) == 1);
  check(traceObject(rt.nativeLoad64(edges), edges) == 1);
  check(traceObject(rt.nativeLoad64(edges), edges) == 0);
  var result = callbacks[0](nested[0]);
  check(result[0].marker == 842 && result[1].marker == 841);

  // This closure mentions T only in its body. Its enclosing invocation has
  // returned, and the reified List<Leaf> argument must still be traced.
  var tests = <bool Function(Object?)>[genericNestedRootTypeTest<Leaf>()];
  var testList = captureList(tests, 1, queue);
  check(listElements(testList, edges) == 1);
  var test = rt.nativeLoad64(edges);
  check(traceObject(test, edges) == 1);
  environment = rt.nativeLoad64(edges);
  check(traceObject(environment, edges) == 1);
  var arguments = rt.nativeLoad64(edges);
  check(traceObject(arguments, edges) == 1);
  var argument = rt.nativeLoad64(edges);
  check(rt.nativeLoad64(argument + abi.typeKindOffset) == abi.typeKindList);
  check(traceObject(argument, edges) == 0);
  check(tests[0](<Leaf>[]) && !tests[0](<int>[]));
  check(roots.rtRootMark() == mark);
}

void floatingRoots(int queue, int edges) {
  Object boxed = 1.25;
  final address = rt.nativeValueBits(boxed);
  final raw = capture(Leaf(609), 609, queue);
  // A double containing an address's bits must remain a non-root word.
  final bits = double.parse(
    rt.nativeValueFromBits(rt.rtDoubleToString(raw)) as String,
  );
  final words = <double>[bits];
  double captured() => bits;
  final count = snapshot(queue);
  check(contains(queue, count, address));
  check(!contains(queue, count, raw));
  check(traceObject(address, edges) == 0);
  check(boxed == 1.25 && words[0] == captured());
  final nullable = <double?>[1.5, null];
  final list = rt.nativeValueBits(nullable);
  check(contains(queue, snapshot(queue), list));
  check(listElements(list, edges) == 1);
  final element = rt.nativeLoad64(edges);
  check(
    rt.nativeLoad64(
          rt.rtObjectDescriptor(element) + abi.descriptorKindOffset,
        ) ==
        abi.descriptorDoubleBox,
  );
  check(traceObject(element, edges) == 0);
  check(nullable[0] == 1.5);
}

Leaf Function() lateRootFactory(Leaf source) {
  late final Leaf result = Leaf(source.marker + 1);
  return () => result;
}

Object? Function() lateTaggedRootFactory(Leaf source) {
  late Object? result = source;
  return () => result;
}

List<Leaf Function()> lateSharedRootFactory() {
  late Leaf result;
  return [() => result, () => result = Leaf(953)];
}

int Function() lateWordRootFactory(int raw) {
  late int word = raw;
  return () => word;
}

class LateRoot {
  late Leaf reference = Leaf(955);
  late Object? tagged;
  late double scalar = 2.5;
}

void lateRoots(int queue, int edges) {
  final read = lateRootFactory(Leaf(951));
  final closure = rt.nativeValueBits(read);
  check(traceObject(closure, edges) == 1);
  final cell = rt.nativeLoad64(edges);
  check(rt.nativeLoad64(rt.rtObjectDescriptor(cell)) == abi.lateCellClassId);
  // Before reading, only the initializer retains the source object.
  check(traceObject(cell, edges) == 1);
  final initializer = rt.nativeLoad64(edges);
  check(traceObject(initializer, edges) == 1);
  final source = findMarker(edges, 1, 951);
  check(source != 0);
  check(contains(queue, snapshot(queue), closure));
  check(read().marker == 952);
  // Successful initialization releases the thunk and keeps the typed payload.
  check(traceObject(cell, edges) == 1);
  check(findMarker(edges, 1, 952) != 0);
  check(contains(queue, snapshot(queue), closure));
  check(read().marker == 952);

  final shared = lateSharedRootFactory();
  final getter = rt.nativeValueBits(shared[0]);
  final setter = rt.nativeValueBits(shared[1]);
  check(traceObject(getter, edges) == 1);
  final empty = rt.nativeLoad64(edges);
  check(traceObject(empty, edges) == 0);
  check(traceObject(setter, edges) == 1);
  check(rt.nativeLoad64(edges) == empty);
  check(shared[1]().marker == 953 && shared[0]().marker == 953);
  check(traceObject(empty, edges) == 1);
  check(findMarker(edges, 1, 953) != 0);

  final tagged = lateTaggedRootFactory(Leaf(954));
  check(traceObject(rt.nativeValueBits(tagged), edges) == 1);
  final taggedCell = rt.nativeLoad64(edges);
  check(tagged() is Leaf);
  check(traceObject(taggedCell, edges) == 1);
  check(findMarker(edges, 1, 954) != 0);
  check((tagged() as Leaf).marker == 954);
  final word = lateWordRootFactory(source);
  check(word() == source);
  check(traceObject(rt.nativeValueBits(word), edges) == 1);
  check(traceObject(rt.nativeLoad64(edges), edges) == 0);
  check(word() == source);

  final object = LateRoot();
  final address = rt.nativeValueBits(object);
  check(traceObject(address, edges) == 0);
  check(object.scalar == 2.5);
  check(traceObject(address, edges) == 0);
  object.tagged = Leaf(956);
  check(object.reference.marker == 955);
  check(traceObject(address, edges) == 2);
  check(findMarker(edges, 2, 955) != 0);
  check(findMarker(edges, 2, 956) != 0);
  check(object.scalar == 2.5 && (object.tagged as Leaf).marker == 956);
}

void stackTraceRoots(int queue, int edges) {
  final trace = StackTrace.current;
  final text = trace.toString();
  check(text.indexOf('stackTraceRoots') >= 0);
  check(traceObject(rt.nativeValueBits(trace), edges) == 1);
  check(rt.nativeLoad64(edges) == rt.nativeValueBits(text));
  final count = snapshot(queue);
  check(contains(queue, count, rt.nativeValueBits(trace)));
  check(trace.toString() == text);

  final metadata = rt.nativeMetadataAddress(abi.metadataFrames);
  final table =
      metadata + rt.nativeLoad64(metadata + abi.metadataFrameTableOffset);
  final frames =
      table + rt.nativeLoad64(table + abi.frameTableDescriptorsOffset);
  final length = rt.nativeLoad64(table + abi.frameTableCountOffset);
  check(length > 1);
  var previousEnd = 0;
  for (var i = 0; i < length; i++) {
    final descriptor = frames + i * abi.frameDescriptorBytes;
    final start =
        descriptor + rt.nativeLoad64(descriptor + abi.frameStartOffset);
    final end = descriptor + rt.nativeLoad64(descriptor + abi.frameEndOffset);
    check(start < end && start >= previousEnd);
    check(rtFrameDescriptor(start) == descriptor);
    check(rtFrameDescriptor(end - 1) == descriptor);
    final bytes = rt.nativeLoad64(descriptor + abi.frameSizeOffset);
    final mask = rt.nativeLoad64(descriptor + abi.frameSavedMaskOffset);
    check((mask & ~511) == 0);
    if (i == 0) {
      check(rtFrameDescriptor(start - 1) == 0);
      check(bytes == -1 && mask == 0);
      check(rt.nativeLoad64(descriptor + abi.frameNameOffset) == 0);
    } else {
      check(bytes >= 0 && bytes % 16 == 0);
      var saved = rt.nativeLoad64(descriptor + abi.frameSavedOffset);
      for (var register = 0; register < 9; register++) {
        if ((mask & (1 << register)) != 0) {
          check(saved <= -8 && saved >= -bytes && saved % 8 == 0);
          saved -= 8;
        }
      }
      final name =
          descriptor + rt.nativeLoad64(descriptor + abi.frameNameOffset);
      check((rt.nativeValueFromBits(name) as String).isNotEmpty);
    }
    previousEnd = end;
  }
  check(rtFrameDescriptor(previousEnd) == 0);
}

Never exceptionRootThrow(int queue, int depth) {
  if (depth > 0) exceptionRootThrow(queue, depth - 1);
  check(findMarker(queue, snapshot(queue), 970) != 0);
  throw Leaf(971);
}

void exceptionRootCatch(int queue) {
  final retained = Leaf(970);
  try {
    exceptionRootThrow(queue, 16);
  } on Leaf catch (value, trace) {
    final count = snapshot(queue);
    check(findMarker(queue, count, 970) != 0);
    check(findMarker(queue, count, 971) == rt.nativeValueBits(value));
    check(contains(queue, count, rt.nativeValueBits(trace)));
    check(retained.marker == 970 && value.marker == 971);
    check(trace.toString().indexOf('exceptionRootThrow') >= 0);
  }
  ArgumentError? retainedError;
  try {
    throw ArgumentError.value(Leaf(972), 'payload', Leaf(973));
  } on ArgumentError catch (error, trace) {
    retainedError = error;
    final count = snapshot(queue);
    check(contains(queue, count, rt.nativeValueBits(error)));
    check(contains(queue, count, rt.nativeValueBits(trace)));
    final fields = traceObject(rt.nativeValueBits(error), queue);
    check(contains(queue, fields, rt.nativeValueBits(error.stackTrace)));
    check(error.stackTrace.toString() == trace.toString());
    check(
      findMarker(queue, fields, 972) == rt.nativeValueBits(error.invalidValue),
    );
    check(findMarker(queue, fields, 973) == rt.nativeValueBits(error.message));
  }
  heap.rtCollect();
  check(
    retainedError!.stackTrace.toString().indexOf('exceptionRootCatch') >= 0,
  );
}

void exceptionRoots(int queue) {
  exceptionRootCatch(queue);
  final mark = roots.rtRootMark();
  final values = genericRootList<Leaf>(Leaf(974));
  final wrong = <Leaf>[];
  final typeOwner = genericRootList<List<Leaf>>(wrong);
  final list = rt.nativeValueBits(values);
  final listType = rt.nativeLoad64(list + abi.listTypeOffset);
  final wrongType = rt.rtListElementType(rt.nativeValueBits(typeOwner));
  for (var operation = 0; operation < 7; operation++) {
    try {
      final value = rt.nativeValueBits(wrong);
      if (operation == 0) rt.rtListGet(list, 0, wrongType);
      if (operation == 1) rt.rtListSet(list, 0, value, wrongType);
      if (operation == 2) rt.rtListAdd(list, value, wrongType);
      if (operation == 3) rt.rtListInsert(list, 0, value, wrongType);
      if (operation == 4) rt.rtListFilledChecked(1, value, 1, listType);
      if (operation == 5) rt.rtListRemoveLast(list, wrongType);
      if (operation == 6) rt.rtListRemoveAt(list, 0, wrongType);
      check(false);
    } on TypeError catch (error, trace) {
      check(roots.rtRootMark() == mark);
      heap.rtCollect();
      final count = snapshot(queue);
      check(contains(queue, count, rt.nativeValueBits(error)));
      check(contains(queue, count, rt.nativeValueBits(trace)));
      check(error.stackTrace.toString() == trace.toString());
    } finally {
      check(roots.rtRootMark() == mark);
    }
    check(values.length == 1 && values[0].marker == 974);
    check(identical(typeOwner[0], wrong) && wrong.isEmpty);
  }
  for (final floating in [false, true]) {
    try {
      final source = 'xinvalid number'.substring(1);
      if (floating) {
        double.parse(source);
      } else {
        int.parse(source);
      }
      check(false);
    } on FormatException catch (error, trace) {
      heap.rtCollect();
      final count = snapshot(queue);
      check(contains(queue, count, rt.nativeValueBits(error)));
      check(contains(queue, count, rt.nativeValueBits(trace)));
      final fields = traceObject(rt.nativeValueBits(error), queue);
      check(contains(queue, fields, rt.nativeValueBits(error.source)));
      check(error.source == 'invalid number');
      check(error.message.isNotEmpty);
      check(floating ? error.offset == null : error.offset == 0);
    }
  }
  final count = snapshot(queue);
  check(findMarker(queue, count, 970) == 0);
  check(findMarker(queue, count, 971) == 0);
  final metadata = rt.nativeMetadataAddress(abi.metadataHandlers);
  final table =
      metadata + rt.nativeLoad64(metadata + abi.metadataHandlerTableOffset);
  final entries =
      table + rt.nativeLoad64(table + abi.handlerTableEntriesOffset);
  final length = rt.nativeLoad64(table + abi.handlerTableCountOffset);
  check(length > 0);
  var previous = 0;
  for (var i = 0; i < length; i++) {
    final entry = entries + i * abi.handlerEntryBytes;
    final pc = entry + rt.nativeLoad64(entry + abi.handlerReturnOffset);
    final landing = entry + rt.nativeLoad64(entry + abi.handlerLandingOffset);
    check(pc > previous);
    final frame = rtFrameDescriptor(pc);
    check(frame != 0 && rtFrameDescriptor(landing) == frame);
    previous = pc;
  }
}

Leaf finallyRootReturn(int queue, bool replace) {
  try {
    return Leaf(980);
  } finally {
    check(findMarker(queue, snapshot(queue), 980) != 0);
    if (replace) return Leaf(984);
  }
}

int finallyTraceBits = 0;

Never finallyRootThrow(int queue) {
  try {
    try {
      throw Leaf(981);
    } catch (value, trace) {
      finallyTraceBits = rt.nativeValueBits(trace);
      rethrow;
    }
  } finally {
    var count = snapshot(queue);
    check(findMarker(queue, count, 981) != 0);
    check(contains(queue, count, finallyTraceBits));
    try {
      throw Leaf(982);
    } on Leaf catch (value) {
      count = snapshot(queue);
      check(findMarker(queue, count, 981) != 0);
      check(findMarker(queue, count, 982) == rt.nativeValueBits(value));
      check(contains(queue, count, finallyTraceBits));
    }
  }
}

void finallyRootCatch(int queue) {
  check(finallyRootReturn(queue, false).marker == 980);
  check(finallyRootReturn(queue, true).marker == 984);
  try {
    finallyRootThrow(queue);
  } on Leaf catch (value, trace) {
    check(value.marker == 981);
    check(rt.nativeValueBits(trace) == finallyTraceBits);
    check(trace.toString().indexOf('finallyRootThrow') >= 0);
  }
}

void finallyRoots(int queue) {
  finallyRootCatch(queue);
  final count = snapshot(queue);
  check(findMarker(queue, count, 980) == 0);
  check(findMarker(queue, count, 981) == 0);
  check(findMarker(queue, count, 982) == 0);
  check(findMarker(queue, count, 984) == 0);
  check(!contains(queue, count, finallyTraceBits));
}

class CollectionNode {
  Leaf leaf;
  CollectionNode? next;
  Object? tagged;
  CollectionNode(this.leaf, this.tagged);
}

class CollectionThrow {
  String toString() => throw Leaf(1600);
}

Leaf? collectedGlobal;
Object? collectedTagged;

void collectionRoots(int queue) {
  check(collectedGlobal == null && collectedTagged == null);
  collectedGlobal = Leaf(1601);
  collectedTagged = Leaf(1602);
  final values = <Leaf>[for (var i = 0; i < 4096; i++) Leaf(i)];
  final first = CollectionNode(Leaf(1500), 9223372036854775807);
  final second = CollectionNode(Leaf(1501), values);
  first.next = second;
  second.next = first;
  var cell = Leaf(1502);
  final read = () => cell.marker;
  final bound = first.leaf.read;
  final mark = roots.rtRootMark();
  final raw = capture(Leaf(1503), 1503, queue);
  roots.rtRootPush(raw, abi.storageRef);
  for (var round = 0; round < 4; round++) {
    var sum = 0;
    for (var i = 0; i < 50000; i++) {
      final discarded = <Leaf>[Leaf(i), Leaf(i + 1)];
      sum += discarded[0].marker + discarded[1].marker;
    }
    check(sum == 2500000000);
    heap.rtCollect();
    check(collectedGlobal!.marker == 1601);
    check((collectedTagged as Leaf).marker == 1602);
    check(first.next!.next == first);
    check(first.tagged == 9223372036854775807);
    check(second.tagged == values);
    check(bound() == 1500 && read() == 1502 + round);
    check((rt.nativeValueFromBits(raw) as Leaf).marker == 1503);
    for (var i = 0; i < values.length; i++) check(values[i].marker == i);
    cell = Leaf(1503 + round);
  }
  roots.rtRootRestore(mark);
  final throwing = <Object>[CollectionThrow()];
  try {
    throwing.toString();
    check(false);
  } catch (error) {
    heap.rtCollect();
    check((error as Leaf).marker == 1600);
    check(roots.rtRootMark() == mark);
  }
  throwing.clear();
  throwing.add('recovered');
  check(throwing.toString() == '[recovered]');
  collectedGlobal = null;
  collectedTagged = null;
}

void main(List<String> args) {
  var queue = rt.rtMap(capacity * 8);
  var edges = rt.rtMap(capacity * 8);
  finallyRoots(queue);
  exceptionRoots(queue);
  stackTraceRoots(queue, edges);
  lateRoots(queue, edges);
  typeGraphRoots(queue, edges);
  genericTypeRoots(queue, edges);
  listPatternRoots(queue, edges);
  destructuringRoots(queue, edges);
  switchStatementRoots(queue, edges);
  closureRoots(queue, edges);
  noGcRoots(queue);
  builderRoots(queue, edges);
  var keep = Leaf(111);
  var count = snapshot(queue);
  check(findMarker(queue, count, 111) != 0);
  check(keep.marker == 111);
  var onlyInput = capture(Leaf(110), 110, queue);
  check(traceObject(onlyInput, edges) == 0);
  count = many(
    Leaf(120),
    Leaf(121),
    Leaf(122),
    Leaf(123),
    Leaf(124),
    Leaf(125),
    Leaf(126),
    Leaf(127),
    Leaf(128),
    queue,
  );
  var i = 120;
  while (i <= 128) {
    check(findMarker(queue, count, i) != 0);
    i++;
  }
  count = recurse(3, queue);
  i = 140;
  while (i <= 143) {
    check(findMarker(queue, count, i) != 0);
    i++;
  }
  var acrossIndirect = Leaf(160);
  Object watched = Watch(queue);
  check(watched.toString() == 'watched');
  check(acrossIndirect.marker == 160);
  var raw = capture(Leaf(170), 170, queue);
  count = snapshot(queue);
  check(findMarker(queue, count, 170) == 0);
  check(rt.nativeLoad64(raw + abi.objectHeaderBytes) == 170);
  check(globalLeaf.marker == 180);
  check(globalBox is int);
  var cacheAddress = captureList(cached, 2, queue);
  count = snapshot(queue);
  check(findMarker(queue, count, 180) != 0);
  check(contains(queue, count, cacheAddress));
  var boxed = 0;
  i = 0;
  while (i < count) {
    var object = rt.nativeLoad64(queue + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor + abi.descriptorKindOffset) ==
        abi.descriptorIntBox) {
      check(
        rt.nativeLoad64(object + abi.objectHeaderBytes) == 9223372036854775807,
      );
      boxed = object;
    }
    i++;
  }
  check(boxed != 0);
  check(traceObject(boxed, edges) == 0);
  check(listElements(cacheAddress, edges) == 2);
  var first = rt.nativeLoad64(edges);
  var second = rt.nativeLoad64(edges + 8);
  check(listElements(first, edges) == 0);
  check(traceObject(second, edges) == 0);
  final constructWide = WideOwnFields.new;
  var wide = constructWide(
    Leaf(201),
    Leaf(202),
    Leaf(203),
    Leaf(204),
    Leaf(205),
    Leaf(206),
  ) as DerivedWide;
  wide.p61 = raw;
  var wideAddress = capture(wide, 200, queue);
  count = traceObject(wideAddress, edges);
  check(count == 6);
  check(findMarker(edges, count, 201) != 0);
  check(findMarker(edges, count, 202) != 0);
  check(findMarker(edges, count, 203) != 0);
  check(findMarker(edges, count, 204) != 0);
  check(findMarker(edges, count, 205) != 0);
  check(findMarker(edges, count, 206) != 0);
  check(wide.delayed.marker == 207);
  count = traceObject(wideAddress, edges);
  check(count == 7 && findMarker(edges, count, 207) != 0);
  check(wide.tail.marker == 201);
  var refs = <Leaf?>[Leaf(301), null, Leaf(302)];
  var tagged = <Object?>[Leaf(303), false, 9223372036854775807, Leaf(304)];
  var refsAddress = captureList(refs, 3, queue);
  var taggedAddress = captureList(tagged, 4, queue);
  count = listElements(refsAddress, edges);
  check(count == 2 && findMarker(edges, count, 302) != 0);
  refs.removeLast();
  count = listElements(refsAddress, edges);
  check(count == 1 && findMarker(edges, count, 301) != 0);
  refs.clear();
  check(listElements(refsAddress, edges) == 0);
  count = listElements(taggedAddress, edges);
  check(count == 3 && findMarker(edges, count, 304) != 0);
  tagged.removeLast();
  count = listElements(taggedAddress, edges);
  check(count == 2 && findMarker(edges, count, 303) != 0);
  tagged.clear();
  check(listElements(taggedAddress, edges) == 0);
  floatingRoots(queue, edges);
  runtimeOwnership(queue, edges);
  constantObjectRoots(queue, edges);
  collectionRoots(queue);
  rt.rtUnmap(edges, capacity * 8);
  rt.rtUnmap(queue, capacity * 8);
  print('roots ok');
}
