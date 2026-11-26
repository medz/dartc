import 'dart:typed_data';

import 'package:dartc/heap.dart';
import 'package:dartc/src/emit/stack_maps.dart';

/// Classes as the collector sees them: the offsets of their references.
const classes = <List<int>>[
  [],
  [8],
  [8, 16, 24],
  [16],
  [8],
];

/// Which class has objects that are arrays of references, after a field.
const arrayClass = 4;

/// The bytes of an object of each class.
const sizes = [16, 16, 32, 24, 24];

/// Weak classes, after these: their kind, the references that they keep, and
/// their other fields.
const weakClasses = <(int, List<int>, List<int>)>[
  (2, [], [8, 16]),
  (3, [], [8, 16, 24]),
  (4, [8, 16], [24, 32, 40, 48, 56, 64, 72]),
  (5, [8], []),
];

/// Ends a simulated throw.
final class const Resumed() implements Exception;

/// Memory with a stack, globals and tables, where wrong accesses throw.
final class SimulatedMachine({
  @override final bool collectsAlways = false,
  var int available = 1 << 40,
}) implements Machine {
  final _regions = <int, ByteData>{};
  int _next = 0x100000, mapped = 0, mostMapped = 0, mappings = 0;
  int collections = 0;
  late final int _frames, _maps, _classes, _globals, _handlers, _native;

  /// References held by functions that are running, innermost last.
  final List<List<int>> frames = [];

  /// Which of them C calls, rather than the one before.
  final Set<int> calledFromC = {};

  /// The number of references each kind of frame holds, by return address.
  static const _kinds = [0, 1, 2, 5, _wide];

  /// The number of references in frames where the last one is far away.
  static const _wide = 3, _far = -8 * 40000;
  static const globalCount = 4, _frameBytes = 1 << 23;
  static const _code = 0x5000;

  /// What the machine maps for itself.
  static int get ownBytes => SimulatedMachine().mapped;

  this {
    // The program does not map its stack.
    _frames = _next;
    _regions[_frames] = ByteData(_frameBytes);
    _next += _frameBytes + 0x1000;
    _globals = mapMemory(globalCount * 8);
    _handlers = mapMemory(4096);
    _native = mapMemory(8);
    final words = <int>[];
    for (final (i, offsets) in classes.indexed) {
      words.addAll([offsets.length, i == arrayClass ? 1 : 0, ...offsets]);
    }
    for (final (kind, kept, others) in weakClasses) {
      words.addAll([kept.length, kind, ...kept, ...others]);
    }
    final count = classes.length + weakClasses.length;
    _classes = mapMemory((count + words.length) * 4);
    var at = count * 4;
    for (final (i, fields) in [
      for (final offsets in classes) offsets.length,
      for (final (_, kept, others) in weakClasses) kept.length + others.length,
    ].indexed) {
      store32(_classes + i * 4, at);
      at += 8 + fields * 4;
    }
    for (final (i, word) in words.indexed) {
      store32(_classes + (count + i) * 4, word);
    }
    _makeMaps();
    mostMapped = mapped;
  }

  /// Where a kind of frame has its references, from its address.
  static List<int> _offsetsOf(int count) => [
    for (var i = 1; i <= count; i++)
      count == _wide && i == count ? _far : -8 * i,
  ];

  /// Each kind returns to its own address.
  void _makeMaps() {
    final encoded = ByteData.sublistView(
      encodeStackMaps([
        for (final (i, count) in _kinds.indexed)
          StackMap(100 + i * 4, _offsetsOf(count)),
      ]),
    );
    _maps = mapMemory(encoded.lengthInBytes);
    for (var at = 0; at < encoded.lengthInBytes; at += 4) {
      store32(_maps + at, encoded.getUint32(at, .little));
    }
  }

  /// Lays out [frames] in memory. The first returns outside the program.
  @override
  int get callBlock => throw UnsupportedError('Calls of C');
  @override
  void callNative(int block) => throw UnsupportedError('Calls of C');

  @override
  int get frameAddress {
    collections++;
    var address = _frames + _frameBytes - 16;
    store64(address, 0);
    store64(address + 8, 0x77777777);
    var native = 0;
    for (final (i, references) in frames.indexed) {
      if (calledFromC.contains(i)) {
        // The call of C, whose frame tells about the one before, and C itself.
        store64(address - 8, native);
        native = address;
        store64(address - 64, 0x33333333);
        store64(address - 56, 0x77777777);
        address -= 64;
      }
      final kind = _kinds.indexOf(references.length);
      // The caller's references are below its frame address.
      final offsets = _offsetsOf(references.length);
      for (final (j, reference) in references.indexed) {
        store64(address + offsets[j], reference);
      }
      final callee = address + (offsets.lastOrNull ?? 0) - 64;
      store64(callee, address);
      store64(callee + 8, _code + 100 + kind * 4);
      address = callee;
    }
    store64(_native, native);
    return address;
  }

  /// The numbers of references a frame can hold.
  static List<int> get frameSizes => _kinds;

  void setGlobal(int index, int reference) =>
      store64(_globals + index * 8, reference);
  int global(int index) => load64(_globals + index * 8);

  @override
  int get nativeFrame => _native;
  @override
  int get codeStart => _code;
  @override
  int get stackMaps => _maps;
  @override
  int get classTable => _classes;
  @override
  int get globalRoots => _globals;
  @override
  int get globalRootCount => globalCount;

  @override
  int mapMemory(int bytes) {
    if (mapped + bytes > available) return 0;
    final address = _next;
    _regions[address] = ByteData(bytes);
    _next = (address + bytes + 0x1fff) & ~0xfff;
    mapped += bytes;
    mappings++;
    if (mapped > mostMapped) mostMapped = mapped;
    return address;
  }

  @override
  void unmapMemory(int address, int bytes) {
    final region = _regions.remove(address);
    if (region?.lengthInBytes != bytes) throw StateError('Wrong unmapping.');
    mapped -= bytes;
  }

  (ByteData, int) _find(int address, int bytes) {
    for (final MapEntry(key: start, value: region) in _regions.entries) {
      final at = address - start;
      if (at >= 0 && at + bytes <= region.lengthInBytes) return (region, at);
    }
    throw StateError('Invalid address $address.');
  }

  @override
  int load64(int address) {
    final (region, at) = _find(address, 8);
    return region.getInt64(at, .little);
  }

  @override
  void store64(int address, int value) {
    final (region, at) = _find(address, 8);
    region.setInt64(at, value, .little);
  }

  @override
  int load32(int address) {
    final (region, at) = _find(address, 4);
    return region.getUint32(at, .little);
  }

  @override
  int load32Signed(int address) {
    final (region, at) = _find(address, 4);
    return region.getInt32(at, .little);
  }

  @override
  void store32(int address, int value) {
    final (region, at) = _find(address, 4);
    region.setUint32(at, value, .little);
  }

  /// The calls that have handlers, by return address, and where those are.
  final Map<int, int> targets = {};

  /// Where the last throw continued, with what.
  ({int frame, int code, Object exception, Object trace})? resumed;

  @override
  int get handlers {
    store32(_handlers, targets.length);
    for (final (i, offset) in (targets.keys.toList()..sort()).indexed) {
      store32(_handlers + 4 + i * 8, offset);
      store32(_handlers + 8 + i * 8, targets[offset]!);
    }
    return _handlers;
  }

  @override
  int get outputBuffer => throw UnimplementedError();
  @override
  int load8(int address) => throw UnimplementedError();
  @override
  void store8(int address, int value) => throw UnimplementedError();
  @override
  void write(int file, int address, int count) => throw UnimplementedError();
  @override
  void formatDouble(double value, int digits, int address) =>
      throw UnimplementedError();
  @override
  double parseDouble(int address) => throw UnimplementedError();
  @override
  int classNumber(Object object) => throw UnimplementedError();
  @override
  int addressOf(Object object) => throw UnimplementedError();

  @override
  Never resume(int frame, int code, Object exception, Object trace) {
    resumed = (frame: frame, code: code, exception: exception, trace: trace);
    throw const Resumed();
  }

  @override
  Never trap() => throw StateError('Trapped.');
}

/// A program that does nothing after collections.
final class SimulatedProgram() implements Program {
  @override
  void afterCollection() {}

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
