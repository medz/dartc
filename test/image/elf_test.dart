import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:test/test.dart';

/// A file as loaders read it.
final class _Elf(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  int u16(int at) => data.getUint16(at, .little);
  int u32(int at) => data.getUint32(at, .little);
  int u64(int at) => data.getUint64(at, .little);

  int get type => u16(16);
  int get entry => u64(24);

  late final List<_Segment> segments = [
    for (var i = 0; i < u16(56); i++) _Segment(this, u64(32) + i * 56),
  ];

  Iterable<_Segment> get loaded => segments.where((s) => s.type == 1);

  /// Where [address] is in the file.
  int at(int address) {
    final segment = loaded.firstWhere(
      (s) => address >= s.address && address < s.address + s.fileBytes,
    );
    return segment.offset + address - segment.address;
  }

  late final Map<int, List<int>> dynamic = () {
    final segment = segments.singleWhere((s) => s.type == 2);
    final result = <int, List<int>>{};
    for (var i = 0; u64(segment.offset + i * 16) != 0; i++) {
      final entry = segment.offset + i * 16;
      (result[u64(entry)] ??= []).add(u64(entry + 8));
    }
    return result;
  }();

  String text(int offset) {
    final start = at(dynamic[5]!.single) + offset;
    var end = start;
    while (data.getUint8(end) != 0) {
      end++;
    }
    return String.fromCharCodes(data.buffer.asUint8List(start, end - start));
  }

  String symbolName(int index) => text(u32(_symbol(index)));
  int symbolValue(int index) => u64(_symbol(index) + 8);
  int _symbol(int index) => at(dynamic[6]!.single) + index * 24;

  /// The number of the symbol called [name], found as loaders do.
  int? find(String name) {
    final table = at(dynamic[4]!.single);
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash << 4) + unit;
      final high = hash & 0xf0000000;
      hash ^= high >> 24;
      hash &= ~high;
    }
    final buckets = u32(table);
    var index = u32(table + 8 + hash % buckets * 4);
    while (index != 0 && symbolName(index) != name) {
      index = u32(table + 8 + buckets * 4 + index * 4);
    }
    return index == 0 ? null : index;
  }
}

final class _Segment(_Elf elf, int at) {
  final int type = elf.u32(at), flags = elf.u32(at + 4);
  final int offset = elf.u64(at + 8), address = elf.u64(at + 16);
  final int fileBytes = elf.u64(at + 32), memoryBytes = elf.u64(at + 40);
  final int alignment = elf.u64(at + 48);
}

EmittedCode _code({
  int textBytes = 64,
  List<String> externals = const ['puts', 'sin', 'exit'],
  Map<String, String> exports = const {},
}) => EmittedCode(
  Uint8List(textBytes),
  const {'f': 0, 'g': 8},
  [Relocation(0, .call26, 'puts')],
  externals: externals,
  data: {'constant': Uint8List(10)},
  tables: const {
    'table': ['f', 'g'],
  },
  objects: {
    'a': EmittedObject(Uint8List(24), const {8: 'b'}, writable: false),
    'b': EmittedObject(Uint8List(40), const {16: 'a'}, writable: true),
  },
  exports: exports,
);

void main() {
  test('segments have pages of their own', () {
    for (final textBytes in [4, 64, 0x10000 - 64, 0x10000, 0x23458]) {
      final elf = _Elf(linkElf(_code(textBytes: textBytes), entry: 'g'));
      expect(elf.type, 3);
      var page = -1;
      for (final segment in elf.loaded) {
        expect(segment.alignment, 0x10000);
        expect(segment.offset % 0x10000, segment.address % 0x10000);
        expect(segment.address ~/ 0x10000, greaterThan(page));
        final end = segment.address + segment.memoryBytes;
        page = (end - 1) ~/ 0x10000;
        expect(segment.memoryBytes, greaterThanOrEqualTo(segment.fileBytes));
        // Nothing can be both written and run.
        expect(segment.flags & 3, isNot(3));
      }
    }
  });

  test('what only relocations change is protected', () {
    final elf = _Elf(linkElf(_code(), entry: 'f'));
    final protected = elf.segments.singleWhere((s) => s.type == 0x6474e552);
    expect((protected.address + protected.memoryBytes) % 0x10000, 0);
    final segment = elf.loaded.firstWhere(
      (s) => s.address == protected.address,
    );
    expect(segment.memoryBytes, protected.memoryBytes);
    expect(elf.loaded.last.address, greaterThan(protected.address));
  });

  test('programs have their entry and their libraries', () {
    final elf = _Elf(linkElf(_code(), entry: 'g'));
    final code = elf.loaded.firstWhere((s) => s.flags & 1 != 0);
    expect(elf.entry, code.address + 8);
    expect(elf.dynamic[1]!.map(elf.text), ['libc.so.6', 'libm.so.6']);
    final plain = _Elf(linkElf(_code(externals: ['puts']), entry: 'g'));
    expect(plain.dynamic[1]!.map(plain.text), ['libc.so.6']);
    final interpreter = elf.segments.singleWhere((s) => s.type == 3);
    expect(
      elf.data.buffer.asUint8List(interpreter.offset, interpreter.fileBytes),
      [...'/lib/ld-linux-aarch64.so.1'.codeUnits, 0],
    );
    expect(() => linkElf(_code(), entry: 'x'), throwsA(isA<ImageError>()));
    expect(
      () => linkElf(_code(externals: ['sin']), entry: 'g'),
      throwsA(isA<ImageError>()),
    );
  });

  test('symbols are found by their names', () {
    final names = [for (var i = 0; i < 50; i++) 'name$i'];
    final code = _code(
      exports: {
        for (final (i, name) in names.indexed) name: i.isEven ? 'f' : 'g',
      },
    );
    final elf = _Elf(linkElfLibrary(code, name: 'libx.so'));
    expect(elf.text(elf.dynamic[14]!.single), 'libx.so');
    expect(elf.segments.where((s) => s.type == 3), isEmpty);
    final start = elf.loaded.firstWhere((s) => s.flags & 1 != 0).address;
    for (final (i, name) in names.indexed) {
      expect(elf.symbolValue(elf.find(name)!), start + (i.isEven ? 0 : 8));
    }
    for (final name in code.externals) {
      expect(elf.symbolValue(elf.find(name)!), 0);
    }
    expect(elf.find('name50'), isNull);
    expect(elf.find('f'), isNull);
  });

  test('relocations are those of slots and of references', () {
    final elf = _Elf(linkElf(_code(), entry: 'f'));
    final at = elf.at(elf.dynamic[7]!.single), bytes = elf.dynamic[8]!.single;
    expect(bytes, 5 * 24);
    final kinds = [for (var i = 0; i < 5; i++) elf.u32(at + i * 24 + 8)];
    expect(kinds, [1025, 1025, 1025, 1027, 1027]);
    final symbols = [
      for (var i = 0; i < 3; i++) elf.symbolName(elf.u32(at + i * 24 + 12)),
    ];
    expect(symbols, ['puts', 'sin', 'exit']);
    // a refers to b, which is where that refers to a from, less 16.
    final toB = elf.u64(at + 3 * 24 + 16), toA = elf.u64(at + 4 * 24 + 16);
    expect(elf.u64(at + 3 * 24), toA + 8);
    expect(elf.u64(at + 4 * 24), toB + 16);
  });

  test('the same code gives the same bytes', () {
    expect(linkElf(_code(), entry: 'f'), linkElf(_code(), entry: 'f'));
  });
}
