import 'package:dartc/src/runtime/event_loop.dart';
import 'package:dartc/src/runtime/finalization.dart';
import 'package:dartc/src/runtime/heap.dart';
import 'package:test/test.dart';

final class Alive(final Set<Object> values) implements Liveness {
  @override
  bool isAlive(Object? value) => values.contains(value);
}

void main() {
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
