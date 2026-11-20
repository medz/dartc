import 'heap.dart';
import '../../lib/runtime/contracts.dart';

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
  final void Function(T) _callback, {
  super.isNative,
}) extends FinalizerRegistration {
  @override
  void attach(Object value, covariant T token, {Object? detach}) =>
      super.attach(value, token, detach: detach);

  @override
  void _invoke(Object? token) => _callback(token as T);
}

// The empty slot denotes a token already removed by detach or delivery.
// An attached caller may independently register a null token.
enum _NullToken() {
  value,
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
  Object? _token = token ?? _NullToken.value;
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
        _finish(record, deliver: false);
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
      if (_finish(record, deliver: true)) return true;
    }
    return false;
  }

  // A linked record may have been cancelled since it was enqueued.
  // Claim its token and finish accounting before invoking user code.
  bool _finish(FinalizationRecord record, {required bool deliver}) {
    final stored = record._token;
    if (stored == null) return false;
    record._token = null;
    _externalBytes -= record.externalSize;
    record._unlink();
    record._state = deliver ? .delivered : .detached;
    if (deliver) {
      record.owner._invoke(identical(stored, _NullToken.value) ? null : stored);
    }
    return true;
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
        _finish(record, deliver: true);
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
        _finish(record, deliver: record.owner.isNative);
      }
    }
    for (var record = _head; record != null; record = _head) {
      _head = record._queueNext;
      if (_head == null) _tail = null;
      record._queueNext = null;
      if (record._state == .queued) {
        _finish(record, deliver: record.owner.isNative);
      }
    }
  }
}
