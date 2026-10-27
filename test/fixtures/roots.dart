import '../../lib/src/runtime.dart' as rt;
import '../../lib/src/layout.dart' as abi;

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

Leaf globalLeaf = Leaf(180);
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

int snapshot(int queue) {
  return rt.rtTraceRoots(rt.nativeFramePointer(), queue, capacity);
}

int capture(Object? value, int marker, int queue) {
  var count = rt.rtTraceRoots(rt.nativeFramePointer(), queue, capacity);
  var object = findMarker(queue, count, marker);
  check(object != 0);
  return object;
}

int captureList(Object? value, int length, int queue) {
  var count = rt.rtTraceRoots(rt.nativeFramePointer(), queue, capacity);
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
  check(rt.rtTraceObject(object, queue, capacity) == 1);
  var backing = rt.nativeLoad64(queue);
  return rt.rtTraceObject(backing, queue, capacity);
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

void capacityFailure(Object? value) {
  print('before');
  rt.rtTraceRoots(rt.nativeFramePointer(), 0, 0);
}

void runtimeOwnership(int queue, int edges) {
  var mark = rt.rtRootMark();
  var first = capture(Leaf(401), 401, queue);
  check(!contains(queue, snapshot(queue), first));
  rt.rtRootPush(first, abi.storageRef);
  check(contains(queue, snapshot(queue), first));
  var nested = rt.rtRootMark();
  var second = capture(Leaf(402), 402, queue);
  rt.rtRootPush(second, abi.storageTagged);
  var persistent = rt.rtGlobalRootNew(second, abi.storageRef);
  rt.rtRootRestore(nested);
  check(contains(queue, snapshot(queue), second));
  rt.rtRootRestore(mark);
  var count = snapshot(queue);
  check(!contains(queue, count, first) && contains(queue, count, second));
  rt.rtGlobalRootSet(persistent, first);
  check(rt.rtGlobalRootValue(persistent) == first);
  count = snapshot(queue);
  check(contains(queue, count, first) && !contains(queue, count, second));
  rt.rtGlobalRootSet(persistent, 0);
  check(!contains(queue, snapshot(queue), first));

  rt.rtRootPush(0, abi.storageRef);
  rt.rtRootPush(0, abi.storageTagged);
  rt.rtRootPush(abi.valueFalse, abi.storageTagged);
  rt.rtRootPush(abi.valueTrue, abi.storageTagged);
  rt.rtRootPush(rt.rtBoxInt(-7), abi.storageTagged);
  check(rt.rtRootMark() == mark);
  var box = rt.rtBoxInt(9223372036854775807);
  rt.rtRootPush(box, abi.storageTagged);
  check(contains(queue, snapshot(queue), box));
  rt.rtRootRestore(mark);
  check(!contains(queue, snapshot(queue), box));

  rt.rtRootPush(second, abi.storageRef);
  var i = 1;
  while (i < 1100) {
    rt.rtRootPush(first, abi.storageTagged);
    i++;
  }
  check(rt.rtRootMark() == mark + 1100);
  count = snapshot(queue);
  check(contains(queue, count, first) && contains(queue, count, second));
  rt.rtRootRestore(mark);
  count = snapshot(queue);
  check(!contains(queue, count, first) && !contains(queue, count, second));
  var stable = rt.rtGlobalRootNew(first, abi.storageTagged);
  i = 0;
  while (i < 1100) {
    rt.rtGlobalRootNew(0, abi.storageRef);
    i++;
  }
  check(rt.rtGlobalRootValue(stable) == first);
  rt.rtGlobalRootSet(persistent, second);
  count = snapshot(queue);
  check(contains(queue, count, first) && contains(queue, count, second));
  rt.rtGlobalRootSet(stable, 0);
  rt.rtGlobalRootSet(persistent, 0);
  count = snapshot(queue);
  check(!contains(queue, count, first) && !contains(queue, count, second));

  var watched = Watch(queue, true, edges);
  var rendering = <Object>[watched, 9223372036854775807, 'tail', true, false];
  watched.input = captureList(rendering, 5, queue);
  check(
    rendering.toString() == '[watched, 9223372036854775807, tail, true, false]',
  );
  check(rt.rtRootMark() == mark);
  Object fallback = Leaf(403);
  check(fallback.toString() == "Instance of 'Leaf'");
  check(rt.rtRootMark() == mark);
  var cyclic = <Object>[];
  cyclic.add(cyclic);
  check(cyclic.toString() == '[[...]]');
  check(rt.rtRootMark() == mark);
}

void constantObjectRoots(int queue, int edges) {
  var mark = rt.rtRootMark();
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
  check(rt.rtRootMark() == mark);
  var count = rt.rtTraceObject(parentAddress, edges, capacity);
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
  count = rt.rtTraceObject(childAddress, edges, capacity);
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
  check(rt.rtRootMark() == mark);
}

@pragma('dartc:no-gc')
int noGcScope(int raw, int queue) {
  var mark = rt.rtRootMark();
  var i = 0;
  while (i < 1100) {
    rt.rtRootPush(raw, abi.storageRef);
    i++;
  }
  var count = rt.rtTraceRoots(rt.nativeFramePointer(), queue, capacity);
  rt.rtRootRestore(mark);
  return count;
}

void noGcRoots(int queue) {
  var raw = capture(Leaf(601), 601, queue);
  var mark = rt.rtRootMark();
  var count = noGcScope(raw, queue);
  check(contains(queue, count, raw));
  check(rt.rtRootMark() == mark);
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
  var mark = rt.rtRootMark();
  var words = <int>[701];
  var wordType = rt.nativeLoad64(
    captureList(words, 1, queue) + abi.listTypeOffset,
  );
  var intType = rt.rtTypeArgument(wordType);
  var objects = <Object?>[];
  var list = captureList(objects, 0, queue);
  var objectType = rt.nativeLoad64(list + abi.listTypeOffset);
  rt.rtListAdd(list, 9223372036854775807, intType);
  check(objects.length == 1 && rt.rtRootMark() == mark);
  var full = rt.nativeLoad64(list + abi.listCapacityOffset);
  var i = 1;
  while (i < full) {
    rt.rtListAdd(list, i, intType);
    i++;
  }
  rt.rtListAdd(list, 9223372036854775807, intType);
  check(objects.length == full + 1 && rt.rtRootMark() == mark);
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
  var refs = <Leaf>[Leaf(702)];
  var refType = rt.nativeLoad64(
    captureList(refs, 1, queue) + abi.listTypeOffset,
  );
  var child = capture(refs[0], 702, queue);
  sharedFilledEdges(rt.rtListFilled(3, child, 1, refType), child, edges);
  check(rt.rtRootMark() == mark);
  sharedFilledEdges(rt.rtListFilled(3, wide, 1, objectType), wide, edges);
  check(rt.rtRootMark() == mark);
  var rawWords = rt.rtListFilled(3, child, 1, wordType);
  check(listElements(rawWords, edges) == 0 && rt.rtRootMark() == mark);
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

void closureRoots(int queue, int edges) {
  var patterns = <int Function()>[
    switch (Leaf(806)) {
      Leaf value => () => value.marker,
    },
  ];
  var patternList = captureList(patterns, 1, queue);
  check(listElements(patternList, edges) == 1);
  var pattern = rt.nativeLoad64(edges);
  check(rt.rtTraceObject(pattern, edges, capacity) == 1);
  check(findMarker(edges, 1, 806) != 0);
  check(patterns[0]() == 806);
  var callables = <int Function()>[Leaf(805)];
  var callableList = captureList(callables, 1, queue);
  check(listElements(callableList, edges) == 1);
  var callable = rt.nativeLoad64(edges);
  check(rt.rtTraceObject(callable, edges, capacity) == 1);
  check(findMarker(edges, 1, 805) != 0);
  check(callables[0]() == 805);
  var methods = <int Function()>[Leaf(804).read];
  var methodList = captureList(methods, 1, queue);
  check(listElements(methodList, edges) == 1);
  var method = rt.nativeLoad64(edges);
  var descriptor = rt.rtObjectDescriptor(method);
  check(rt.nativeLoad64(descriptor) == abi.boundMethodClassId);
  check(rt.rtTraceObject(method, edges, capacity) == 1);
  check(findMarker(edges, 1, 804) != 0);
  check(methods[0]() == 804);
  var callbacks = closureGraph();
  var list = captureList(callbacks, 2, queue);
  check(listElements(list, edges) == 2);
  var read = rt.nativeLoad64(edges);
  var next = rt.nativeLoad64(edges + 8);
  check(rt.rtTraceObject(read, edges, capacity) == 3);
  check(findMarker(edges, 3, 802) != 0);
  var shared = 0;
  var cells = 0;
  for (var i = 0; i < 3; i++) {
    var object = rt.nativeLoad64(edges + i * 8);
    var descriptor = rt.rtObjectDescriptor(object);
    if (rt.nativeLoad64(descriptor) == abi.captureCellClassId) {
      cells++;
      var count = rt.rtTraceObject(object, queue, capacity);
      if (count == 1) {
        check(findMarker(queue, count, 801) != 0);
        shared = object;
      } else {
        check(count == 0);
      }
    }
  }
  check(cells == 2 && shared != 0);
  check(rt.rtTraceObject(next, edges, capacity) == 2);
  check(contains(edges, 2, shared));
  check(callbacks[0]() == 1603 && callbacks[1]() == 1);
  check(rt.rtTraceObject(shared, edges, capacity) == 1);
  check(findMarker(edges, 1, 803) != 0);
  check(callbacks[0]() == 1606);
}

void main(List<String> args) {
  if (args.isNotEmpty && args[0] == 'capacity') {
    capacityFailure(Leaf(190));
    return;
  }
  var queue = rt.rtMap(capacity * 8);
  var edges = rt.rtMap(capacity * 8);
  closureRoots(queue, edges);
  noGcRoots(queue);
  builderRoots(queue, edges);
  var keep = Leaf(111);
  var count = snapshot(queue);
  check(findMarker(queue, count, 111) != 0);
  check(keep.marker == 111);
  var onlyInput = capture(Leaf(110), 110, queue);
  check(rt.rtTraceObject(onlyInput, edges, capacity) == 0);
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
  check(rt.rtTraceObject(boxed, edges, capacity) == 0);
  check(listElements(cacheAddress, edges) == 2);
  var first = rt.nativeLoad64(edges);
  var second = rt.nativeLoad64(edges + 8);
  check(listElements(first, edges) == 0);
  check(rt.rtTraceObject(second, edges, capacity) == 0);
  var wide = Wide(Leaf(201), Leaf(202), Leaf(203), Leaf(204));
  wide.p61 = raw;
  var wideAddress = capture(wide, 200, queue);
  count = rt.rtTraceObject(wideAddress, edges, capacity);
  check(count == 4);
  check(findMarker(edges, count, 201) != 0);
  check(findMarker(edges, count, 202) != 0);
  check(findMarker(edges, count, 203) != 0);
  check(findMarker(edges, count, 204) != 0);
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
  runtimeOwnership(queue, edges);
  constantObjectRoots(queue, edges);
  rt.rtUnmap(edges, capacity * 8);
  rt.rtUnmap(queue, capacity * 8);
  print('roots ok');
}
