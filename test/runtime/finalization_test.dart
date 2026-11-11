import 'package:dartc/src/runtime/finalization.dart';
import 'package:dartc/src/runtime/heap.dart';
import 'package:test/test.dart';

final class Alive(final Set<Object> values) implements Liveness {
  @override
  bool isAlive(Object? value) => values.contains(value);
}

final class Roots() implements ReferenceVisitor {
  final values = <Object>[];
  @override
  void visit(Object? value) {
    if (value != null) values.add(value);
  }
}

void main() {
  test('required shutdown registrations remain roots until detached', () {
    final queue = FinalizationQueue(), roots = Roots(), key = Object();
    final owner = FinalizerHandle((_) {}, runOnShutdown: true);
    final record = queue.attach(owner, Object(), 'token', detachKey: key);
    queue.visitPending(roots);
    expect(roots.values, [record]);
    queue.detach(owner, key);
    roots.values.clear();
    queue.visitPending(roots);
    expect(roots.values, isEmpty);
  });
  test('shutdown closes registration and continues after callback failure', () {
    final queue = FinalizationQueue(), events = <Object>[];
    final failure = StateError('callback');
    final owner = FinalizerHandle((token) {
      events.add(token);
      if (token == 'first') throw failure;
    }, runOnShutdown: true);
    queue.attach(owner, Object(), 'second');
    queue.attach(owner, Object(), 'first');
    expect(queue.finishShutdown, throwsA(same(failure)));
    expect(events, ['first', 'second']);
    expect(queue.finishShutdown, returnsNormally);
    expect(() => queue.attach(owner, Object(), 'late'), throwsStateError);
  });
  test('queues once and invokes callbacks only after resuming', () {
    final queue = FinalizationQueue(), events = <Object>[];
    final owner = FinalizerHandle(events.add);
    final record = queue.attach(owner, Object(), 'token');
    final live = Alive({record});
    queue.stage(live);
    queue.stage(live);
    expect(events, isEmpty);
    expect(record.state, FinalizationState.queued);
    queue.deliver();
    queue.deliver();
    expect(events, ['token']);
    expect(record.state, FinalizationState.delivered);
  });

  test('detached and unreachable registrations do not deliver', () {
    final queue = FinalizationQueue(), events = <Object>[];
    final owner = FinalizerHandle(events.add), key = Object();
    final detached = queue.attach(owner, Object(), 'detached', detachKey: key);
    queue.attach(owner, Object(), 'unreachable');
    queue.detach(owner, key);
    queue.stage(Alive({detached}));
    queue.deliver();
    expect(events, isEmpty);
    expect(detached.state, FinalizationState.detached);
  });

  test(
    'shutdown runs required callbacks once and discards optional delivery',
    () {
      final queue = FinalizationQueue(), events = <Object>[];
      final native = FinalizerHandle(events.add, runOnShutdown: true);
      final dart = FinalizerHandle(events.add);
      queue.attach(native, Object(), 'native');
      queue.attach(dart, Object(), 'dart');
      queue.finishShutdown();
      queue.finishShutdown();
      expect(events, ['native']);
    },
  );
}
