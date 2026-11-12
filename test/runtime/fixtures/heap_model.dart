import '../../../sdk/runtime/heap.dart';

enum WeakKind() {
  none,
  target,
  ephemeron,
}

final class Node() {
  final strong = <Node>[];
  WeakKind kind = .none;
  Node? key;
  Node? value;
}

final class ModelRoots() implements RootSet {
  final values = <Object>[];
  bool deferred = false, stopped = false, closed = false;

  @override
  bool stop() {
    if (deferred) return false;
    stopped = true;
    return true;
  }

  @override
  void visit(ReferenceVisitor visitor) => values.forEach(visitor.visit);

  @override
  void resume() => stopped = false;

  @override
  void close() => closed = true;
}

final class ModelFinalization() implements Finalization {
  int shutdowns = 0;

  @override
  void visitPending(ReferenceVisitor visitor) {}

  @override
  void stage(Liveness live) {}

  @override
  void finishShutdown() => shutdowns++;
}

final class HeapModel() implements ObjectAccess {
  final roots = ModelRoots();
  final finalization = ModelFinalization();
  late final heap = Heap(this, roots, finalization);
  final pages = <Page, List<Node>>{};
  final locations = Map<Object, (Page, int)>.identity();
  int released = 0;

  Page addPage([int capacity = 64]) {
    final page = Page(this, pages.length * 4096, 64, capacity);
    pages[page] = List.generate(capacity, (_) => Node());
    heap.addPage(page);
    return page;
  }

  Node allocate(Page page) {
    final slot = page.reserve();
    if (slot < 0) throw StateError('Full page');
    final node = Node();
    pages[page]![slot] = node;
    locations[node] = (page, slot);
    return node;
  }

  @override
  Page? ownerOf(Object value) => locations[value]?.$1;

  @override
  int slotOf(Page page, Object value) => locations[value]!.$2;

  @override
  Object objectAt(Page page, int slot) => pages[page]![slot];

  @override
  void visitStrong(Object value, ReferenceVisitor visitor) =>
      (value as Node).strong.forEach(visitor.visit);

  @override
  void traceConditional(Object value, Liveness live, ReferenceVisitor visitor) {
    final node = value as Node;
    if (node.kind == .ephemeron && live.isAlive(node.key)) {
      visitor.visit(node.value);
    }
  }

  @override
  void clearWeak(Object value, Liveness live) {
    final node = value as Node;
    if (node.kind != .none && !live.isAlive(node.key)) {
      node.key = null;
      node.value = null;
    }
  }

  @override
  void releasePage(Page page) => released++;

  @override
  Never corruptHeap() => throw StateError('Corrupt heap');
}
