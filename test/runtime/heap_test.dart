import '../../sdk/runtime/heap.dart';
import '../../sdk/runtime/allocator.dart' show allocationFailure;

import 'package:test/test.dart';

import 'fixtures/heap_model.dart';

void main() {
  test(
    'allocation failure preserves the preallocated error and empty trace',
    () {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          allocationFailure();
        } catch (error, trace) {
          expect(error, same(const OutOfMemoryError()));
          expect(trace, same(StackTrace.empty));
        }
      }
    },
  );

  test('reuses one page record across repeated empty heap cycles', () {
    final model = HeapModel();
    final page = model.addPage();
    for (var i = 0; i < 100; i++) {
      for (var slot = 0; slot < 64; slot++) {
        model.allocate(page);
      }
      expect(page.used, 64);
      model.heap.collect();
      expect(model.heap.emptyPage, same(page));
      page.replaceStorage(8192 + i * 4096, 64, 64);
      expect(model.heap.availablePage(64), same(page));
    }
    model.heap.close();
    expect(model.heap.emptyPage, isNull);
  });
  test('keeps the high bit live and reuses dead slots after sweeping', () {
    final model = HeapModel(), page = model.addPage();
    final nodes = List.generate(64, (_) => model.allocate(page));
    model.roots.values.add(nodes.last);
    expect(page.reserve(), -1);
    expect(model.heap.collect(), isTrue);
    expect(page.used, 1);
    expect(page.reserve(), 0);
    model.roots.values.clear();
    model.heap.collect();
    expect(page.used, 0);
  });

  test('drains deep cyclic graphs without recursion or duplicate work', () {
    final model = HeapModel();
    final nodes = <Node>[];
    for (var i = 0; i < 128; i++) {
      final page = model.addPage();
      for (var slot = 0; slot < 64; slot++) {
        nodes.add(model.allocate(page));
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].strong.addAll([nodes[(i + 1) % nodes.length], nodes.first]);
    }
    model.roots.values.add(nodes.first);
    model.heap.collect();
    expect(
      model.pages.keys.map((p) => p.used).reduce((a, b) => a + b),
      nodes.length,
    );
    model.roots.values.clear();
    model.heap.collect();
    expect(model.pages.keys.map((p) => p.used), everyElement(0));
  });

  test(
    'requeues a drained page when a cross-page edge reaches an earlier slot',
    () {
      final model = HeapModel(),
          first = model.addPage(),
          second = model.addPage();
      final earlier = model.allocate(first);
      Node last = earlier;
      for (var i = 1; i < 64; i++) {
        last = model.allocate(first);
      }
      final middle = model.allocate(second);
      last.strong.add(middle);
      middle.strong.add(earlier);
      earlier.strong.add(last);
      model.roots.values.add(last);
      model.heap.collect();
      expect(first.used, 2);
      expect(second.used, 1);
    },
  );

  test('weak references do not retain targets or dead ephemeron cycles', () {
    final model = HeapModel(), page = model.addPage();
    final weak = model.allocate(page)..kind = .target;
    weak.key = model.allocate(page);
    final pair = model.allocate(page)..kind = .ephemeron;
    pair.key = model.allocate(page);
    pair.value = model.allocate(page)..strong.add(pair.key!);
    pair.key!.strong.add(pair.value!);
    model.roots.values.addAll([weak, pair]);
    model.heap.collect();
    expect(page.used, 2);
    expect(weak.key, isNull);
    expect(pair.key, isNull);
    expect(pair.value, isNull);
  });

  test(
    'permanent control cycles trace managed children on every collection',
    () {
      final model = HeapModel(), page = model.addPage();
      final first = Node(), second = Node();
      final child = model.allocate(page);
      first.strong.addAll([second, child]);
      second.strong.add(first);
      model.roots.controls.addAll([first, second]);
      for (var i = 0; i < 2; i++) {
        model.heap.collect();
        expect(page.used, 1);
        expect(first.strong.last, same(child));
      }
      first.strong.remove(child);
      model.heap.collect();
      expect(page.used, 0);
    },
  );

  test('all module identities trace strong, weak and conditional fields', () {
    final model = HeapModel(), page = model.addPage();
    final first = Node(), second = Node();
    final key = model.allocate(page),
        value = model.allocate(page),
        dead = model.allocate(page);
    final weak = Node()
      ..kind = .target
      ..key = dead;
    final pair = Node()
      ..kind = .ephemeron
      ..key = key
      ..value = value;
    first.strong.add(second);
    second.strong.addAll([first, key]);
    model.roots.modules.addAll([first, second, weak, pair]);
    expect(model.ownerOf(first), isNull);
    expect(model.ownerOf(second), isNull);
    for (var i = 0; i < 2; i++) {
      model.heap.collect();
      expect(page.used, 2);
      expect(weak.key, isNull);
      expect(pair.key, same(key));
      expect(pair.value, same(value));
    }
    second.strong.remove(key);
    model.heap.collect();
    expect(page.used, 0);
    expect(pair.key, isNull);
    expect(pair.value, isNull);
  });

  test('control weak slots clear dead targets without retaining them', () {
    final model = HeapModel(), page = model.addPage();
    final live = model.allocate(page), dead = model.allocate(page);
    final retained = Node()..kind = .target;
    final cleared = Node()..kind = .target;
    retained.key = live;
    cleared.key = dead;
    model.roots.controls.addAll([retained, cleared]);
    model.roots.values.add(live);
    model.heap.collect();
    expect(page.used, 1);
    expect(retained.key, same(live));
    expect(cleared.key, isNull);
    model.roots.values.clear();
    model.heap.collect();
    expect(page.used, 0);
    expect(retained.key, isNull);
  });

  test('control and managed ephemerons share one reachability fixed point', () {
    final model = HeapModel(), page = model.addPage();
    final first = model.allocate(page)..kind = .ephemeron;
    final second = Node()..kind = .ephemeron;
    first.key = model.allocate(page);
    first.value = model.allocate(page);
    second.key = first.value;
    second.value = model.allocate(page);
    model.roots.controls.add(second);
    model.roots.values.addAll([first, first.key!]);
    model.heap.collect();
    expect(page.used, 4);
    expect(second.value, isNotNull);
    model.roots.values.remove(first.key);
    model.heap.collect();
    expect(page.used, 1);
    expect(first.key, isNull);
    expect(first.value, isNull);
    expect(second.key, isNull);
    expect(second.value, isNull);
  });

  test('control ephemerons retain values for permanent keys', () {
    final model = HeapModel(), page = model.addPage();
    final key = Node(), pair = Node()..kind = .ephemeron;
    pair.key = key;
    pair.value = model.allocate(page);
    model.roots.controls.addAll([key, pair]);
    model.heap.collect();
    expect(page.used, 1);
  });

  test(
    'all control tracing phases reject allocation and collection reentry',
    () {
      final model = HeapModel(), page = model.addPage();
      final phases = <HeapPhase>[];
      void check() {
        phases.add(model.heap.phase);
        expect(model.heap.collect, throwsStateError);
        expect(page.reserve, throwsStateError);
        expect(() => model.heap.availablePage(64), throwsStateError);
      }

      model.roots.onVisit = check;
      model.roots.onConditional = check;
      model.roots.onClearWeak = check;
      model.heap.collect();
      expect(phases, [
        HeapPhase.marking,
        HeapPhase.weakProcessing,
        HeapPhase.weakProcessing,
      ]);
      expect(model.heap.phase, HeapPhase.running);
      expect(model.roots.stopped, isFalse);
    },
  );

  test(
    'conditional references reach a fixed point across reverse dependencies',
    () {
      final model = HeapModel(), page = model.addPage();
      final second = model.allocate(page)..kind = .ephemeron;
      final first = model.allocate(page)..kind = .ephemeron;
      final key = model.allocate(page),
          nextKey = model.allocate(page),
          value = model.allocate(page);
      first.key = key;
      first.value = nextKey;
      second.key = nextKey;
      second.value = value;
      model.roots.values.addAll([first, second, key]);
      model.heap.collect();
      expect(page.used, 5);
      expect(second.value, same(value));
    },
  );

  test('deferral leaves the heap unchanged and shutdown is idempotent', () {
    final model = HeapModel(), page = model.addPage();
    model.allocate(page);
    model.roots.deferred = true;
    expect(model.heap.collect(), isFalse);
    expect(page.used, 1);
    expect(model.heap.phase, HeapPhase.running);
    model.heap.close();
    model.heap.close();
    expect(model.released, 1);
    expect(model.finalization.shutdowns, 1);
    expect(model.roots.closed, isTrue);
    expect(() => model.heap.collect(), throwsStateError);
    expect(page.reserve, throwsStateError);
  });

  test('rejects foreign heap roots and invalid page capacities', () {
    final model = HeapModel(), other = HeapModel();
    final page = other.addPage();
    final foreign = other.allocate(page);
    model.locations[foreign] = (page, 0);
    model.roots.values.add(foreign);
    expect(model.heap.collect, throwsStateError);
    expect(() => other.heap.addPage(Page(other, 0, 64, 65)), throwsStateError);
  });
}
