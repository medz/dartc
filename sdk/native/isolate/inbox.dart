// Messages between isolates, in memory that all of them can reach.
import 'dart:_heap/machine.dart' show load64, store32, store64;
import 'dart:_heap/objects.dart' show randomBits, registerEvents;
import 'dart:_internal' show EventOrder, EventSource;
import 'dart:ffi' show Int32, Int64, Native, Void;

@Native<Int64 Function(Int64)>(symbol: 'malloc')
external int _allocate(int bytes);

@Native<Void Function(Int64)>(symbol: 'free')
external void _free(int address);

@Native<Int32 Function(Int64, Int64)>(symbol: 'pthread_mutex_init')
external int _initLock(int lock, int attributes);

@Native<Int32 Function(Int64)>(symbol: 'pthread_mutex_lock')
external int _lock(int lock);

@Native<Int32 Function(Int64)>(symbol: 'pthread_mutex_unlock')
external int _unlock(int lock);

@Native<Int32 Function(Int64)>(symbol: 'pipe')
external int _pipe(int files);

@Native<Int64 Function(Int32, Int64, Int64)>(symbol: 'read')
external int _readPipe(int file, int address, int count);

@Native<Int64 Function(Int32, Int64, Int64)>(symbol: 'write')
external int _writePipe(int file, int address, int count);

@Native<Int32 Function(Int32)>(symbol: 'close')
external int _closeFile(int file);

@Native<Int32 Function(Int64, Int64, Int32)>(symbol: 'poll')
external int _poll(int files, int count, int milliseconds);

// An inbox: a lock, the first and the last message, the ends of a pipe that
// wakes its isolate, its state, and a copy of the name of its isolate. The
// lock guards all but the reading end.
const _first = 64, _last = 72, _reading = 80, _writing = 88, _state = 96;
const _name = 104, _inboxBytes = 112;

// Its states: whether its isolate takes messages, and whether there is a byte
// in the pipe.
const _isOpen = 1, _isWoken = 2;

// A message: the next one, the number of its port and where it is copied.
const _nextMessage = 0, _messagePort = 8, _messageData = 16;
const _messageBytes = 24;

/// What `poll` reads and writes: a file and what it waits for, then what
/// happened.
const _pollBytes = 8, _pollIn = 1;

/// Makes an inbox that is open, whose isolate is woken through a pipe.
int _newInbox() {
  final inbox = _allocate(_inboxBytes);
  if (inbox == 0 || _pipe(inbox + _reading) != 0) throw OutOfMemoryError();
  // The pipe gives two 32-bit numbers.
  final files = load64(inbox + _reading);
  store64(inbox + _reading, files & 0xffffffff);
  store64(inbox + _writing, files >> 32);
  store64(inbox + _first, 0);
  store64(inbox + _last, 0);
  store64(inbox + _state, _isOpen);
  store64(inbox + _name, 0);
  _initLock(inbox, 0);
  return inbox;
}

/// The inbox that the isolate is given when it starts, or 0 for the first one.
int _givenInbox = 0;

/// The name of the isolate of [inbox], while it is running.
String? _nameOf(int inbox) {
  _lock(inbox);
  final name = load64(inbox + _name);
  final isOpen = load64(inbox + _state) & _isOpen != 0;
  final result = isOpen && name != 0 ? _decode(name, frees: false) : null;
  _unlock(inbox);
  return result as String?;
}

/// Lets [inbox] take no more messages, and frees those it has. Its memory is
/// kept for the ports of other isolates that refer to it.
void _closeInbox(int inbox) {
  _lock(inbox);
  var message = load64(inbox + _first);
  final name = load64(inbox + _name);
  store64(inbox + _first, 0);
  store64(inbox + _last, 0);
  store64(inbox + _state, 0);
  store64(inbox + _name, 0);
  _unlock(inbox);
  _closeFile(load64(inbox + _reading));
  _closeFile(load64(inbox + _writing));
  if (name != 0) _freeCopy(name);
  while (message != 0) {
    final next = load64(message + _nextMessage);
    _freeCopy(load64(message + _messageData));
    _free(message);
    message = next;
  }
}

/// Gives [data], a message for the port [port], to [inbox] to handle. It is
/// freed if the inbox no longer takes any.
void _post(int inbox, int port, int data) {
  _lock(inbox);
  final state = load64(inbox + _state);
  if (state & _isOpen == 0) {
    _unlock(inbox);
    _freeCopy(data);
    return;
  }
  final message = _allocate(_messageBytes);
  store64(message + _nextMessage, 0);
  store64(message + _messagePort, port);
  store64(message + _messageData, data);
  final last = load64(inbox + _last);
  store64(last == 0 ? inbox + _first : last + _nextMessage, message);
  store64(inbox + _last, message);
  if (state & _isWoken == 0) {
    store64(inbox + _state, state | _isWoken);
    _writePipe(load64(inbox + _writing), inbox + _state, 1);
  }
  _unlock(inbox);
}

/// A message that has come, with its place among timers.
final class _Arrived(final int number, final int port, final int data);

/// The messages of this isolate, and its ports.
final class _Inbox implements EventSource {
  static final _Inbox current = _Inbox(
    _givenInbox != 0 ? _givenInbox : _newInbox(),
  );

  /// Where its messages come in.
  final int address;

  /// The messages that have come, the first ones first.
  final List<_Arrived> _arrived = [];

  /// The ports that are open, by their numbers.
  final Map<int, _RawReceivePortImpl> ports = {};

  /// How many ports keep the isolate going.
  int keepers = 0;

  /// Memory for waiting.
  final int _waiting = _allocate(_pollBytes);

  _Inbox(this.address) {
    registerEvents(this);
    EventOrder.firstMessage = () =>
        _arrived.isEmpty ? 0x7fffffffffffffff : _arrived.first.number;
  }

  /// A number for a new port, which no other port has.
  int newPort() {
    while (true) {
      final number = (randomBits() << 31 ^ randomBits()) & 0x3fffffffffffffff;
      if (number != 0 && !ports.containsKey(number)) return number;
    }
  }

  /// Gives [data] to the port [port] of this isolate, after what came before.
  void postHere(int port, int data) =>
      _arrived.add(_Arrived(EventOrder.next++, port, data));

  bool get keepsAlive => keepers > 0;

  int get happened {
    _takeMessages();
    final limit = EventOrder.firstTimer();
    var count = 0;
    while (count < _arrived.length && _arrived[count].number < limit) {
      count++;
    }
    return count;
  }

  bool runOne() {
    if (_arrived.isEmpty || _arrived.first.number > EventOrder.firstTimer()) {
      return false;
    }
    final message = _arrived.removeAt(0);
    final port = ports[message.port];
    if (port == null) {
      _freeCopy(message.data);
      return true;
    }
    final value = _decode(message.data);
    final handler = port._handler;
    if (handler != null) handler(value);
    return true;
  }

  void wait(int microseconds) {
    store32(_waiting, load64(address + _reading));
    store32(_waiting + 4, _pollIn);
    final milliseconds = microseconds < 0 ? -1 : (microseconds + 999) ~/ 1000;
    _poll(_waiting, 1, milliseconds);
  }

  void end() {}

  /// Ends what this isolate takes.
  void close() {
    for (final message in _arrived) {
      _freeCopy(message.data);
    }
    _arrived.clear();
    _closeInbox(address);
    _free(_waiting);
  }

  /// Moves what other isolates gave to [_arrived].
  void _takeMessages() {
    if (load64(address + _first) == 0) return;
    _lock(address);
    var message = load64(address + _first);
    store64(address + _first, 0);
    store64(address + _last, 0);
    final state = load64(address + _state);
    if (state & _isWoken != 0) {
      store64(address + _state, state & ~_isWoken);
      _readPipe(load64(address + _reading), _waiting, 1);
    }
    _unlock(address);
    while (message != 0) {
      final next = load64(message + _nextMessage);
      postHere(load64(message + _messagePort), load64(message + _messageData));
      _free(message);
      message = next;
    }
  }
}

/// Sends [message] to the port [port] of [inbox].
void _send(int inbox, int port, Object? message) {
  final data = _encode(message);
  final here = _Inbox.current;
  if (inbox == here.address) {
    here.postHere(port, data);
  } else {
    _post(inbox, port, data);
  }
}

/// A number that no other capability is likely to have.
int _newCapability() => (randomBits() << 32 | randomBits()) & ~(1 << 63);
