// Copies of messages outside the heap, which the isolate that takes them makes
// objects of its own of.
//
// A copy has the number of objects and the first one, then each object: its
// size and its bytes. References to objects in the image, which every isolate
// shares, stay as they are; those to others become their indexes, shifted by 3
// and tagged with 2.
import 'dart:_compact_hash' show adoptCopy;
import 'dart:_heap/collector.dart' show allocate;
import 'dart:_heap/machine.dart'
    show addressOf, classTable, load32, load64, store32, store64;
import 'dart:_heap/objects.dart' show isUnsendable, objectAt;
import 'dart:_heap/types.dart' show objectClassName;
import 'dart:_internal' show reachabilityFence;
import 'dart:developer' show UserTag;
import 'dart:ffi' show DynamicLibrary, Int64, Native, NativeFinalizer;
import 'dart:typed_data';

@Native<Int64 Function(Int64, Int64)>(symbol: 'realloc')
external int _reallocate(int address, int bytes);

// Objects: their flags, and where arrays have their length and elements.
const _flags = 4, _fixed = 4, _length = 16, _elements = 24;

// The word of the kind of a class in its record, and the kinds.
const _kindBits = 127, _bytesFlag = 128, _sizeShift = 8;
const _arrays = 1, _references = 2, _properties = 3;

const _tag = 2, _tagBits = 7;

/// Where the record of the class of the object at [address] is.
int _recordOf(int address) {
  final table = classTable();
  return table + load32(table + load32(address) * 4);
}

/// The bytes of the object at [address] whose class has [record].
int _sizeOf(int address, int record) {
  final word = load32(record + 4), fixed = word >> _sizeShift;
  if (word & _kindBits == _arrays) return fixed + load64(address + _length) * 8;
  if (word & _bytesFlag != 0) return fixed + load64(address + _length);
  return fixed;
}

/// Why [object] cannot be sent, if it cannot.
String? _refusal(Object object) {
  String a(String what) => '(object is a $what)';
  if (object is RawReceivePort) return a('ReceivePort');
  if (object is Finalizer) return a('Finalizer');
  if (object is NativeFinalizer) return a('NativeFinalizer');
  if (object is DynamicLibrary) return a('DynamicLibrary');
  if (object is UserTag) return a('UserTag');
  final kind = load32(_recordOf(addressOf(object)) + 4) & _kindBits;
  if (isUnsendable(object) || kind > _properties) {
    return 'object is unsendable - Class: ${objectClassName(object)} (see '
        'restrictions listed at `SendPort.send()` documentation for more '
        'information)';
  }
  return null;
}

/// A copy of [data] in the heap, if it is typed data outside of it.
Object? _insideCopy(Object data) {
  if (data is! TypedData) return null;
  final record = _recordOf(addressOf(data));
  // Those in the heap are arrays, and views refer to them.
  if (load32(record) != 0 || load32(record + 4) & _bytesFlag != 0) return null;
  return switch (data) {
    Int8List() => Int8List.fromList(data),
    Uint8List() => Uint8List.fromList(data),
    Int16List() => Int16List.fromList(data),
    Uint16List() => Uint16List.fromList(data),
    Int32List() => Int32List.fromList(data),
    Uint32List() => Uint32List.fromList(data),
    Int64List() => Int64List.fromList(data),
    Uint64List() => Uint64List.fromList(data),
    Float32List() => Float32List.fromList(data),
    Float64List() => Float64List.fromList(data),
    _ => null,
  };
}

/// Copies an object graph outside the heap.
final class _Encoder {
  final Map<int, int> _indexes = {};
  final List<int> _objects = [];

  /// The copies made in the heap, until they are copied out.
  final List<Object> _kept = [];

  /// Where weak references are in the copy, and what they refer to.
  final List<int> _weak = [];

  int _buffer = 0, _capacity = 0, _end = 0;

  /// The copy of [message], in memory that [_freeCopy] frees.
  int encode(Object? message) {
    _reserve(16);
    final root = message == null ? 0 : _reference(addressOf(message));
    for (var i = 0; i < _objects.length; i++) {
      _write(_objects[i]);
    }
    for (var i = 0; i < _weak.length; i += 2) {
      final target = _weak[i + 1], index = _indexes[target];
      final isKept = index != null || _isFixed(target);
      final value = index != null ? index << 3 | _tag : target;
      store64(_buffer + _weak[i], isKept ? value : 0);
    }
    store64(_buffer, _objects.length);
    store64(_buffer + 8, root);
    // What is copied is found through addresses only.
    reachabilityFence(message);
    return _buffer;
  }

  static bool _isFixed(int value) =>
      value == 0 || value & 1 != 0 || load32(value + _flags) & _fixed != 0;

  /// What stands for the reference [value] in the copy.
  int _reference(int value) {
    if (_isFixed(value)) return value;
    if (_indexes[value] case final index?) return index << 3 | _tag;
    final object = objectAt(value);
    if (_refusal(object) case final refusal?) {
      throw ArgumentError('Illegal argument in isolate message: $refusal\n');
    }
    final index = _objects.length;
    _indexes[value] = index;
    if (_insideCopy(object) case final copy?) {
      _kept.add(copy);
      _objects.add(addressOf(copy));
    } else {
      _objects.add(value);
    }
    return index << 3 | _tag;
  }

  /// Makes room for [bytes] more, returning where they are.
  int _reserve(int bytes) {
    if (_end + bytes > _capacity) {
      var capacity = _capacity == 0 ? 256 : _capacity * 2;
      while (capacity < _end + bytes) {
        capacity *= 2;
      }
      final grown = _reallocate(_buffer, capacity);
      if (grown == 0) throw OutOfMemoryError();
      _buffer = grown;
      _capacity = capacity;
    }
    final at = _end;
    _end += bytes;
    return at;
  }

  void _write(int address) {
    final record = _recordOf(address), size = _sizeOf(address, record);
    final start = _reserve(8 + (size + 7 & ~7)) + 8;
    store64(_buffer + start - 8, size);
    for (var offset = 0; offset < size; offset += 8) {
      store64(_buffer + start + offset, load64(address + offset));
    }
    final count = load32(record), word = load32(record + 4);
    for (var i = 0; i < count; i++) {
      final offset = load32(record + 8 + i * 4);
      store64(_buffer + start + offset, _reference(load64(address + offset)));
    }
    final kind = word & _kindBits;
    if (kind == _arrays) {
      final length = load64(address + _length);
      for (var i = 0; i < length; i++) {
        final offset = _elements + i * 8;
        store64(_buffer + start + offset, _reference(load64(address + offset)));
      }
    } else if (kind == _references || kind == _properties) {
      // Targets, keys and values, then the link that the collector uses.
      final weak = kind == _references ? 1 : 2;
      for (var i = 0; i <= weak; i++) {
        final offset = load32(record + 8 + (count + i) * 4);
        store64(_buffer + start + offset, 0);
        if (i < weak) _weak.addAll([start + offset, load64(address + offset)]);
      }
    }
  }
}

int _encode(Object? message) => _Encoder().encode(message);

void _freeCopy(int data) => _free(data);

/// Makes objects of the copy [data], and frees it if it [frees].
Object? _decode(int data, {bool frees = true}) {
  final count = load64(data);
  final objects = List<Object?>.filled(count, null);
  final starts = List<int>.filled(count, 0);
  var at = data + 16;
  for (var i = 0; i < count; i++) {
    final size = load64(at);
    starts[i] = at + 8;
    objects[i] = objectAt(_make(at + 8, size));
    at += 8 + (size + 7 & ~7);
  }
  Object? resolve(int value) => value & _tagBits == _tag
      ? objects[value >> 3]
      : value == 0
      ? null
      : objectAt(value);
  for (var i = 0; i < count; i++) {
    _connect(addressOf(objects[i]!), starts[i], resolve);
  }
  final root = resolve(load64(data + 8));
  if (frees) _freeCopy(data);
  for (var i = 0; i < count; i++) {
    adoptCopy(objects[i]!);
  }
  return root;
}

/// An object like the one copied at [from], of [size] bytes, without the
/// references it holds. It creates no other objects.
int _make(int from, int size) {
  final address = allocate(size);
  if (address == 0) throw OutOfMemoryError();
  store32(address, load32(from));
  for (var offset = 8; offset < size; offset += 8) {
    store64(address + offset, load64(from + offset));
  }
  final record = _recordOf(address);
  final count = load32(record), kind = load32(record + 4) & _kindBits;
  // Weak ones have their weak references and their link after the others.
  final other = switch (kind) {
    _references => 2,
    _properties => 3,
    _ => 0,
  };
  for (var i = 0; i < count + other; i++) {
    store64(address + load32(record + 8 + i * 4), 0);
  }
  if (kind == _arrays) {
    final length = load64(address + _length);
    for (var i = 0; i < length; i++) {
      store64(address + _elements + i * 8, 0);
    }
  }
  return address;
}

/// Sets the references of the object at [address] as the copy at [from] tells.
void _connect(int address, int from, Object? Function(int) resolve) {
  final record = _recordOf(address);
  final count = load32(record), kind = load32(record + 4) & _kindBits;
  void set(int offset) {
    final value = resolve(load64(from + offset));
    store64(address + offset, value == null ? 0 : addressOf(value));
  }

  for (var i = 0; i < count; i++) {
    set(load32(record + 8 + i * 4));
  }
  if (kind == _arrays) {
    final length = load64(address + _length);
    for (var i = 0; i < length; i++) {
      set(_elements + i * 8);
    }
  } else if (kind == _references || kind == _properties) {
    final weak = kind == _references ? 1 : 2;
    for (var i = 0; i < weak; i++) {
      set(load32(record + 8 + (count + i) * 4));
    }
  }
}
