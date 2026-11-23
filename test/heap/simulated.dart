import 'dart:typed_data';

import 'package:dartc/heap.dart';

/// Classes as the collector sees them: the offsets of their references.
const classes = <List<int>>[
  [],
  [8],
  [8, 16, 24],
  [16],
];

/// The bytes of an object of each class.
const sizes = [16, 16, 32, 24];

/// Ends a simulated throw.
final class const Resumed() implements Exception;

/// Memory with a stack, globals and tables, where wrong accesses throw.
final class SimulatedMachine({
  @override final bool collectsAlways = false,
  var int available = 1 << 40,
}) implements Machine {
  final _regions = <int, ByteData>{};
  int _next = 0x100000, mapped = 0, mostMapped = 0, collections = 0;
  late final int _frames, _maps, _classes, _globals, _handlers;

  /// References held by functions that are running, innermost last.
  final List<List<int>> frames = [];

  /// The number of references each kind of frame holds, by return address.
  static const _kinds = [0, 1, 2, 5];
  static const globalCount = 4;
  static const _code = 0x5000;

  /// What the machine maps for itself.
  static int get ownBytes => SimulatedMachine().mapped;

  this {
    _frames = mapMemory(1 << 16);
    _globals = mapMemory(globalCount * 8);
    _handlers = mapMemory(4096);
    final words = <int>[];
    for (final offsets in classes) {
      words.addAll([offsets.length, ...offsets]);
    }
    _classes = mapMemory((classes.length + words.length) * 4);
    var at = classes.length * 4;
    for (final (i, offsets) in classes.indexed) {
      store32(_classes + i * 4, at);
      at += 4 + offsets.length * 4;
    }
    for (final (i, word) in words.indexed) {
      store32(_classes + (classes.length + i) * 4, word);
    }
    _makeMaps();
    mostMapped = mapped;
  }

  /// Each kind returns to its own address; records follow the index.
  void _makeMaps() {
    _maps = mapMemory(4096);
    store32(_maps, _kinds.length);
    var at = 4 + _kinds.length * 8;
    for (final (i, count) in _kinds.indexed) {
      store32(_maps + 4 + i * 8, 100 + i * 4);
      store32(_maps + 8 + i * 8, at);
      store32(_maps + at, count);
      for (var j = 0; j < count; j++) {
        store32(_maps + at + 4 + j * 4, (-8 * (j + 1)) & 0xffffffff);
      }
      at += 4 + count * 4;
    }
  }

  /// Lays out [frames] in memory. The first returns outside the program.
  @override
  int get frameAddress {
    collections++;
    var address = _frames + (1 << 16) - 16;
    store64(address, 0);
    store64(address + 8, 0x77777777);
    for (final references in frames) {
      final kind = _kinds.indexOf(references.length);
      // The caller's references are below its frame address.
      for (final (j, reference) in references.indexed) {
        store64(address - 8 * (j + 1), reference);
      }
      final callee = address - references.length * 8 - 64;
      store64(callee, address);
      store64(callee + 8, _code + 100 + kind * 4);
      address = callee;
    }
    return address;
  }

  /// The numbers of references a frame can hold.
  static List<int> get frameSizes => _kinds;

  void setGlobal(int index, int reference) =>
      store64(_globals + index * 8, reference);
  int global(int index) => load64(_globals + index * 8);

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

  /// What was written to standard error.
  final List<int> errors = [];

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
  void writeError(int byte) => errors.add(byte);

  @override
  Never resume(int frame, int code, Object exception, Object trace) {
    resumed = (frame: frame, code: code, exception: exception, trace: trace);
    throw const Resumed();
  }

  @override
  Never trap() => throw StateError('Trapped.');
}
