import 'heap.dart';
import 'contracts.dart';

enum FinalizationState() {
  attached,
  queued,
  detached,
  delivered,
}

/// Owns registrations whose callback and tokens remain live with this owner.
final class FinalizerHandle(
  final void Function(Object) callback, {
  final bool runOnShutdown = false,
}) {
  FinalizationRecord? _first;
}

/// Retains a token without retaining its target or registry neighbours.
final class FinalizationRecord(
  final FinalizerHandle owner,
  Object target,
  final Object token,
  Object? detachKey,
) {
  @WeakSlot()
  Object? target = target;
  @WeakSlot()
  Object? detachKey = detachKey;
  @WeakSlot()
  FinalizationRecord? _registryNext;
  FinalizationRecord? _ownerNext;
  FinalizationRecord? _queueNext;
  FinalizationRecord? _shutdownPrevious, _shutdownNext;
  FinalizationState _state = .attached;

  /// The registration's lifecycle state.
  FinalizationState get state => _state;
}

/// Queues existing records during collection and delivers them after resuming.
final class FinalizationQueue() implements Finalization {
  @WeakSlot()
  FinalizationRecord? _records;
  FinalizationRecord? _head;
  FinalizationRecord? _tail;
  FinalizationRecord? _shutdown;
  bool _closed = false;

  /// Attaches a registration to its owner and the weak collector registry.
  FinalizationRecord attach(
    FinalizerHandle owner,
    Object target,
    Object token, {
    Object? detachKey,
  }) {
    if (_closed) throw StateError('Finalization is closed.');
    final record = FinalizationRecord(owner, target, token, detachKey);
    record._registryNext = _records;
    _records = record;
    record._ownerNext = owner._first;
    owner._first = record;
    if (owner.runOnShutdown) {
      record._shutdownNext = _shutdown;
      _shutdown?._shutdownPrevious = record;
      _shutdown = record;
    }
    return record;
  }

  /// Detaches registrations that have not already been queued for delivery.
  void detach(FinalizerHandle owner, Object key) {
    var record = owner._first;
    while (record != null) {
      final next = record._ownerNext;
      if (identical(record.detachKey, key)) {
        _unlinkOwner(record);
        _unlinkShutdown(record);
        record._state = .detached;
        record.target = null;
        record.detachKey = null;
      }
      record = next;
    }
  }

  @override
  void visitPending(ReferenceVisitor visitor) {
    visitor.visit(_head);
    visitor.visit(_shutdown);
  }

  @override
  void stage(Liveness live) {
    FinalizationRecord? previous;
    var record = _records;
    while (record != null) {
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
          _unlinkOwner(record);
          _unlinkShutdown(record);
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

  /// Delivers queued callbacks outside collection, removing each record first.
  void deliver() {
    for (var record = _head; record != null; record = _head) {
      _head = record._queueNext;
      if (_head == null) _tail = null;
      record._queueNext = null;
      record._state = .delivered;
      record.owner.callback(record.token);
    }
  }

  @override
  void finishShutdown() {
    if (_closed) return;
    _closed = true;
    Object? failure;
    var record = _records;
    _records = null;
    while (record != null) {
      final next = record._registryNext;
      record._registryNext = null;
      _unlinkOwner(record);
      _unlinkShutdown(record);
      if (record._state == .attached && record.owner.runOnShutdown) {
        record._state = .delivered;
        try {
          record.owner.callback(record.token);
        } catch (error) {
          failure ??= error;
        }
      } else {
        record._state = .detached;
      }
      record = next;
    }
    record = _head;
    _head = null;
    _tail = null;
    while (record != null) {
      final next = record._queueNext;
      record._queueNext = null;
      if (record.owner.runOnShutdown) {
        record._state = .delivered;
        try {
          record.owner.callback(record.token);
        } catch (error) {
          failure ??= error;
        }
      } else {
        record._state = .detached;
      }
      record = next;
    }
    if (failure case final error?) throw error;
  }

  void _unlinkOwner(FinalizationRecord removed) {
    FinalizationRecord? previous;
    var record = removed.owner._first;
    while (record != null) {
      if (identical(record, removed)) {
        if (previous == null) {
          removed.owner._first = record._ownerNext;
        } else {
          previous._ownerNext = record._ownerNext;
        }
        record._ownerNext = null;
        return;
      }
      previous = record;
      record = record._ownerNext;
    }
  }

  void _unlinkShutdown(FinalizationRecord record) {
    if (!record.owner.runOnShutdown || record._state != .attached) return;
    final previous = record._shutdownPrevious, next = record._shutdownNext;
    if (previous == null) {
      _shutdown = next;
    } else {
      previous._shutdownNext = next;
    }
    next?._shutdownPrevious = previous;
    record._shutdownPrevious = null;
    record._shutdownNext = null;
  }
}
