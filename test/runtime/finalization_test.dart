import '../../sdk/runtime/event_loop.dart';
import '../../sdk/runtime/finalization.dart';
import '../../sdk/runtime/heap.dart';

import 'package:test/test.dart';

final class Alive(final Set<Object> values) implements Liveness {
  @override
  bool isAlive(Object? value) => values.contains(value);
}

final class References() implements ReferenceVisitor {
  final values = <Object?>[];
  @override
  void visit(Object? value) => values.add(value);
}

void main() {
  test(
    'native records retain registration, account bytes and run before events',
    () {
      final queue = FinalizationQueue(), events = <Object?>[];
      final native = FinalizerHandle(queue, events.add, isNative: true);
      final dart = FinalizerHandle(queue, events.add), key = Object();
      final live = Object();
      final first = queue.attach(native, Object(), 'native', externalSize: 100);
      final second = queue.attach(
        native,
        live,
        'cancelled',
        detachKey: key,
        externalSize: 200,
      );
      final event = queue.attach(dart, Object(), 'dart');
      final references = References();
      queue.visitPending(references);
      expect(references.values, containsAll([first, second]));
      expect(references.values, isNot(contains(event)));
      expect(queue.externalBytes, 300);
      queue.stage(Alive({first, second, event, live}));
      queue.drainNative();
      expect(events, ['native']);
      expect(queue.externalBytes, 200);
      native.detach(key);
      native.detach(key);
      expect(queue.externalBytes, 0);
      EventLoop(queue).run();
      queue.finishShutdown();
      expect(events, ['native', 'dart']);
      expect(() => queue.attach(native, Object(), null), throwsStateError);
    },
  );

  test('shutdown delivers native callbacks once, including live targets', () {
    final queue = FinalizationQueue(), events = <Object?>[];
    final native = FinalizerHandle(queue, events.add, isNative: true);
    final first = queue.attach(native, Object(), 'attached', externalSize: 32);
    final second = queue.attach(native, Object(), 'queued', externalSize: 64);
    queue.stage(Alive({first, second, first.target!}));
    queue.finishShutdown();
    queue.finishShutdown();
    expect(events, ['attached', 'queued']);
    expect(queue.externalBytes, 0);
    expect(first.state, FinalizationState.delivered);
    expect(second.state, FinalizationState.delivered);
  });

  test('external allocation sizes are checked before registration', () {
    final queue = FinalizationQueue();
    final owner = FinalizerHandle<Object?>(queue, (_) {}, isNative: true);
    expect(
      () => queue.attach(owner, Object(), null, externalSize: -1),
      throwsRangeError,
    );
    queue.attach(owner, Object(), null, externalSize: 0x7fffffffffffffff);
    expect(
      () => queue.attach(owner, Object(), null, externalSize: 1),
      throwsRangeError,
    );
    expect(queue.externalBytes, 0x7fffffffffffffff);
    queue.finishShutdown();
    expect(queue.externalBytes, 0);
  });

  test('microtasks precede events and reentry cannot drain the next event', () {
    final queue = FinalizationQueue(), events = <String>[];
    final loop = EventLoop(queue);
    final owner = FinalizerHandle<String?>(queue, (token) {
      events.add('$token');
      loop.scheduleMicrotasks(() => events.add('microtask'));
      loop.run();
      events.add('return');
    });
    final first = queue.attach(owner, Object(), null);
    final second = queue.attach(owner, Object(), 'second');
    queue.stage(Alive({first, second}));
    queue.stage(Alive({first, second}));
    expect(events, isEmpty);
    loop.scheduleMicrotasks(() => events.add('first'));
    loop.run();
    loop.run();
    expect(events, [
      'first',
      'second',
      'return',
      'microtask',
      'null',
      'return',
      'microtask',
    ]);
    expect(first.state, FinalizationState.delivered);
    expect(second.state, FinalizationState.delivered);
  });

  test('detach cancels queued attachments and preserves other owners', () {
    final queue = FinalizationQueue(), events = <Object?>[];
    final owner = FinalizerHandle(queue, events.add), key = Object();
    final other = FinalizerHandle(queue, events.add);
    final first = queue.attach(owner, Object(), 'first', detachKey: key);
    final second = queue.attach(owner, Object(), 'second', detachKey: key);
    final retained = queue.attach(other, Object(), 'other', detachKey: key);
    queue.attach(owner, Object(), 'unreachable');
    queue.stage(Alive({first, second, retained}));
    owner.detach(key);
    EventLoop(queue).run();
    expect(events, ['other']);
    expect(first.state, FinalizationState.detached);
    expect(second.state, FinalizationState.detached);
  });

  test('shutdown discards pending and attached records without callbacks', () {
    final queue = FinalizationQueue(), events = <Object?>[];
    final owner = FinalizerHandle(queue, events.add), target = Object();
    final attached = queue.attach(owner, target, 'attached');
    final queued = queue.attach(owner, Object(), 'queued');
    queue.stage(Alive({attached, target, queued}));
    queue.finishShutdown();
    queue.finishShutdown();
    EventLoop(queue).run();
    expect(events, isEmpty);
    expect(attached.state, FinalizationState.detached);
    expect(queued.state, FinalizationState.detached);
    expect(() => owner.attach(Object(), 'late'), throwsStateError);
  });
}
