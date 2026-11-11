import 'heap.dart';
import 'contracts.dart';

enum FinalizationState() {
  attached,
  queued,
  detached,
  delivered,
}

/// Keeps registrations alive for exactly as long as their finalizer is alive.
base class FinalizerHandle<T>(
  final FinalizationQueue queue,
  final void Function(T) callback,
) {
  FinalizationRecord? _first;

  void attach(Object value, T token, {Object? detach}) =>
      queue.attach(this, value, token, detachKey: detach);

  void detach(Object key) => queue.detach(this, key);

  void _invoke(Object? token) => callback(token as T);
}

/// Retains its token, but neither its target nor the collector's registry links.
final class FinalizationRecord(
  final FinalizerHandle<Object?> owner,
  Object target,
  Object? token,
  Object? detachKey,
) {
  @WeakSlot()
  Object? target = target;
  @WeakSlot()
  Object? detachKey = detachKey;
  @WeakSlot()
  FinalizationRecord? _registryNext;
  Object? _token = token;
  FinalizationRecord? _ownerPrevious, _ownerNext, _queueNext;
  FinalizationState _state = .attached;

  FinalizationState get state => _state;

  void _unlink() {
    final previous = _ownerPrevious, next = _ownerNext;
    if (previous == null) {
      owner._first = next;
    } else {
      previous._ownerNext = next;
    }
    next?._ownerPrevious = previous;
    _ownerPrevious = null;
    _ownerNext = null;
    target = null;
    detachKey = null;
    _token = null;
  }
}

/// Stages existing records without allocation; the event loop delivers them.
final class FinalizationQueue() implements Finalization {
  @WeakSlot()
  FinalizationRecord? _records;
  FinalizationRecord? _head, _tail;
  bool _closed = false;

  FinalizationRecord attach(
    FinalizerHandle<Object?> owner,
    Object target,
    Object? token, {
    Object? detachKey,
  }) {
    if (_closed) throw StateError('Finalization is closed.');
    final record = FinalizationRecord(owner, target, token, detachKey);
    record._registryNext = _records;
    _records = record;
    record._ownerNext = owner._first;
    owner._first?._ownerPrevious = record;
    owner._first = record;
    return record;
  }

  /// Cancels all matching attachments, including events awaiting delivery.
  void detach(FinalizerHandle<Object?> owner, Object key) {
    for (var record = owner._first; record != null;) {
      final next = record._ownerNext;
      if (identical(record.detachKey, key)) {
        record._unlink();
        record._state = .detached;
      }
      record = next;
    }
  }

  @override
  void visitPending(ReferenceVisitor visitor) => visitor.visit(_head);

  @override
  void stage(Liveness live) {
    FinalizationRecord? previous;
    for (var record = _records; record != null;) {
      final next = record._registryNext;
      final reachable = live.isAlive(record);
      if (!reachable ||
          record._state != .attached ||
          !live.isAlive(record.target)) {
        if (previous == null) {
          _records = next;
        } else {
          previous._registryNext = next;
        }
        record._registryNext = null;
        if (reachable && record._state == .attached) {
          record._state = .queued;
          if (_tail case final tail?) {
            tail._queueNext = record;
          } else {
            _head = record;
          }
          _tail = record;
        }
      } else {
        previous = record;
      }
      record = next;
    }
  }

  /// Removes one event before calling user code, allowing collection in it.
  bool deliverNext() {
    for (var record = _head; record != null; record = _head) {
      _head = record._queueNext;
      if (_head == null) _tail = null;
      record._queueNext = null;
      if (record._state != .queued) continue;
      final token = record._token;
      record._unlink();
      record._state = .delivered;
      record.owner._invoke(token);
      return true;
    }
    return false;
  }

  @override
  void finishShutdown() {
    if (_closed) return;
    _closed = true;
    for (var record = _records; record != null;) {
      final next = record._registryNext;
      record._registryNext = null;
      if (record._state == .attached) record._unlink();
      record._state = .detached;
      record = next;
    }
    _records = null;
    for (var record = _head; record != null;) {
      final next = record._queueNext;
      record._queueNext = null;
      if (record._state == .queued) record._unlink();
      record._state = .detached;
      record = next;
    }
    _head = null;
    _tail = null;
  }
}
