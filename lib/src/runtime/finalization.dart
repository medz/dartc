import 'heap.dart';
import 'contracts.dart';

enum FinalizationState() {
  attached,
  queued,
  detached,
  delivered,
}

/// Owns attachment state without generic operations during tracing.
abstract base class FinalizerRegistration(
  final FinalizationQueue queue, {
  final bool isNative = false,
}) {
  FinalizationRecord? _first;

  void attach(Object value, Object? token, {Object? detach}) =>
      queue.attach(this, value, token, detachKey: detach);

  void detach(Object key) => queue.detach(this, key);

  void _invoke(Object? token);
}

/// Converts tokens at callback delivery, outside the collector's tracing phase.
base class FinalizerHandle<T>(
  super.queue,
  final void Function(T) callback, {
  super.isNative,
}) extends FinalizerRegistration {
  @override
  void attach(Object value, covariant T token, {Object? detach}) =>
      super.attach(value, token, detach: detach);

  @override
  void _invoke(Object? token) => callback(token as T);
}

/// Retains its token, but neither its target nor the collector's registry links.
final class FinalizationRecord(
  final FinalizerRegistration owner,
  Object target,
  Object? token,
  Object? detachKey,
  final int externalSize,
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

/// Stages without allocation, then delivers native callbacks and Dart events.
final class FinalizationQueue() implements Finalization {
  @WeakSlot()
  FinalizationRecord? _records;
  FinalizationRecord? _head, _tail;
  bool _closed = false;
  int _externalBytes = 0;

  int get externalBytes => _externalBytes;

  FinalizationRecord attach(
    FinalizerRegistration owner,
    Object target,
    Object? token, {
    Object? detachKey,
    int externalSize = 0,
  }) {
    if (_closed) throw StateError('Finalization is closed.');
    RangeError.checkValueInInterval(
      externalSize,
      0,
      0x7fffffffffffffff - _externalBytes,
      'externalSize',
    );
    final record = FinalizationRecord(
      owner,
      target,
      token,
      detachKey,
      externalSize,
    );
    _externalBytes += externalSize;
    record._registryNext = _records;
    _records = record;
    record._ownerNext = owner._first;
    owner._first?._ownerPrevious = record;
    owner._first = record;
    return record;
  }

  /// Cancels all matching attachments, including events awaiting delivery.
  void detach(FinalizerRegistration owner, Object key) {
    for (var record = owner._first; record != null;) {
      final next = record._ownerNext;
      if (identical(record.detachKey, key)) {
        _externalBytes -= record.externalSize;
        record._unlink();
        record._state = .detached;
      }
      record = next;
    }
  }

  @override
  void visitPending(ReferenceVisitor visitor) {
    visitor.visit(_head);
    for (var record = _records; record != null; record = record._registryNext) {
      if (record.owner.isNative) visitor.visit(record);
    }
  }

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
        if (!reachable && record._state == .attached) {
          _externalBytes -= record.externalSize;
        }
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
      _deliver(record);
      return true;
    }
    return false;
  }

  void _deliver(FinalizationRecord record) {
    final token = record._token;
    _externalBytes -= record.externalSize;
    record._unlink();
    record._state = .delivered;
    record.owner._invoke(token);
  }

  /// Runs native callbacks after collection, before returning to Dart execution.
  void drainNative() {
    FinalizationRecord? previous;
    for (var record = _head; record != null;) {
      final next = record._queueNext;
      if (record.owner.isNative) {
        if (previous == null) {
          _head = next;
        } else {
          previous._queueNext = next;
        }
        if (_tail == record) _tail = previous;
        record._queueNext = null;
        if (record._state == .queued) _deliver(record);
        previous = null;
        record = _head;
      } else {
        previous = record;
        record = next;
      }
    }
  }

  @override
  void finishShutdown() {
    if (_closed) return;
    _closed = true;
    for (var record = _records; record != null; record = _records) {
      _records = record._registryNext;
      record._registryNext = null;
      if (record._state == .attached) {
        if (record.owner.isNative) {
          _deliver(record);
        } else {
          _externalBytes -= record.externalSize;
          record._unlink();
          record._state = .detached;
        }
      }
    }
    for (var record = _head; record != null; record = _head) {
      _head = record._queueNext;
      if (_head == null) _tail = null;
      record._queueNext = null;
      if (record._state == .queued) {
        if (record.owner.isNative) {
          _deliver(record);
        } else {
          _externalBytes -= record.externalSize;
          record._unlink();
          record._state = .detached;
        }
      }
    }
  }
}
