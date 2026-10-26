import '../../lib/src/runtime.dart' as rt;
import '../../lib/src/layout.dart' as abi;

const capacity = 512;

class Leaf {
  int marker;
  Leaf(this.marker);
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
  Watch(this.queue);

  String toString() {
    var count = snapshot(queue);
    check(findMarker(queue, count, 160) != 0);
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

void main(List<String> args) {
  if (args.isNotEmpty) {
    capacityFailure(Leaf(190));
    return;
  }
  var queue = rt.rtMap(capacity * 8);
  var edges = rt.rtMap(capacity * 8);
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
  rt.rtUnmap(edges, capacity * 8);
  rt.rtUnmap(queue, capacity * 8);
  print('roots ok');
}
