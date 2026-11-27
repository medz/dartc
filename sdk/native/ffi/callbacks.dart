// Functions of C that programs make.
import 'dart:_heap/machine.dart' show load64, store64;
import 'dart:_heap/objects.dart'
    show callbackInfo, callbacks, registerEvents, takePosted, waitPosted;
import 'dart:_internal' show EventSource, isFirstIsolate;

/// Does what such a function does, given where the block of the call is, and
/// what is passed on the stack.
typedef _Callback = void Function(int block, int stack);

const _entryBytes = 8, _infoBytes = 8, _listenerBit = 32, _numberShift = 33;
const _mostCallbacks = 2048;
const _postedSlot = 8, _postedInfo = 16, _postedBlock = 24, _blockBytes = 208;

/// What each of them does, if it is there.
final List<_Callback?> _made = [];

/// The numbers of those that were there before, the first ones first.
final List<int> _free = [];
int _count = 0;

/// Makes a function that does what [callback] does, for which [stackBytes] are
/// on the stack, perhaps later. Gives its address.
int _makeCallback(_Callback callback, int stackBytes, bool isLater) {
  // Their table is shared, and calls from C reach the first isolate only.
  if (!isFirstIsolate) {
    throw UnsupportedError(
      'Functions of C in isolates other than the first are not supported yet.',
    );
  }
  final int slot;
  if (_made.length < _mostCallbacks) {
    slot = _made.length;
    _made.add(callback);
  } else if (_free.isNotEmpty) {
    slot = _free.removeAt(0);
    _made[slot] = callback;
  } else {
    throw OutOfMemoryError();
  }
  final bit = isLater ? 1 << _listenerBit : 0;
  final number = _count++ << _numberShift;
  store64(callbackInfo() + slot * _infoBytes, number | bit | stackBytes);
  return callbacks() + slot * _entryBytes;
}

void _forgetCallback(int address) {
  final slot = (address - callbacks()) ~/ _entryBytes;
  _made[slot] = null;
  _free.add(slot);
}

void _runCallback(int slot, int block, int stack) {
  final callback = _made[slot];
  if (callback != null) callback(block, stack);
}

/// Calls from C that are done later.
class _Posted implements EventSource {
  /// How many functions are there that could be called.
  int open = 0;

  bool get keepsAlive => open > 0;

  /// The addresses of those that have come, the first ones first.
  final List<int> _come = [];

  int get happened {
    for (var next = takePosted(); next != 0; next = takePosted()) {
      _come.add(next);
    }
    return _come.length;
  }

  bool runOne() {
    if (_come.isEmpty) return false;
    final posted = _come.removeAt(0);
    final slot = load64(posted + _postedSlot);
    // It could be another one by now.
    final info = load64(callbackInfo() + slot * _infoBytes);
    if (info == load64(posted + _postedInfo)) {
      final block = posted + _postedBlock;
      _runCallback(slot, block, block + _blockBytes);
    }
    _freeBytes(Pointer<Never>._(posted));
    return true;
  }

  void wait(int microseconds) => waitPosted(microseconds);

  void end() => FinalizerBase.eachEntry(_finalize);
}

final _Posted _posted = _registerPosted();

_Posted _registerPosted() {
  final source = _Posted();
  registerEvents(source);
  return source;
}

/// The function [callback] of C, for `Pointer.fromFunction`.
int _staticCallback(_Callback callback, int stackBytes) =>
    _makeCallback(callback, stackBytes, false);

NativeCallable<T> _localCallable<T extends Function>(
  _Callback callback,
  int stackBytes,
) {
  _posted.open++;
  return _NativeCallableIsolateLocal<T>(
    Pointer<Never>._(_makeCallback(callback, stackBytes, false)),
  );
}

NativeCallable<T> _listeningCallable<T extends Function>(
  _Callback callback,
  int stackBytes,
) {
  _posted.open++;
  final guarded = Zone.current.bindBinaryCallbackGuarded(callback);
  final address = _makeCallback(
    (block, stack) => guarded(block, stack),
    stackBytes,
    true,
  );
  return _Listener<T>(Pointer<Never>._(address));
}

final class _Listener<T extends Function> extends _NativeCallableBase<T> {
  bool _isKeeping = true;

  _Listener(super._pointer);

  @override
  void _close() {
    _keepIsolateAlive = false;
  }

  @override
  void set _keepIsolateAlive(bool value) {
    if (_isKeeping == value) return;
    _isKeeping = value;
    _updateNativeCallableKeepIsolateAliveCounter(value ? 1 : -1);
  }

  @override
  bool get _keepIsolateAlive => _isKeeping;
}

@patch
void _deleteNativeCallable<NS extends NativeFunction>(Pointer<NS> pointer) =>
    _forgetCallback(pointer._address);

@patch
void _updateNativeCallableKeepIsolateAliveCounter<NS extends NativeFunction>(
  int delta,
) {
  _posted.open += delta;
}
