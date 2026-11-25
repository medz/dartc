import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

/// Where objects store their class, as a 32-bit number.
const classOffset = 0;
const _headerBytes = 8, _fieldBytes = 8;

/// Where arrays have the number of their elements, after their only field, and
/// where those are.
const lengthOffset = 16, elementsOffset = 24;

const _tableSymbol = '.dispatch', _holeSymbol = '.hole';

/// Overlays sparse [rows] in one list, so that entry c of row i is at its
/// offset plus c. Offsets can be negative; indexes of entries are not.
({List<int> offsets, List<T?> entries}) packRows<T extends Object>(
  List<Map<int, T>> rows,
) {
  final offsets = List.filled(rows.length, 0);
  final entries = <T?>[];
  // Where the next entry may be that is not taken, at or after each.
  final free = <int>[];
  int nextFree(int at) {
    var found = at;
    while (found < free.length && free[found] != found) {
      found = free[found];
    }
    // What was followed is shorter from now on.
    for (var i = at; i < found;) {
      final next = free[i];
      free[i] = found;
      i = next;
    }
    return found;
  }

  // The fullest rows are hardest to place. Sorting by index too keeps the
  // result the same on every run.
  final order = [for (var i = 0; i < rows.length; i++) i]
    ..sort((a, b) {
      final size = rows[b].length.compareTo(rows[a].length);
      return size != 0 ? size : a.compareTo(b);
    });
  for (final i in order) {
    final row = rows[i];
    if (row.isEmpty) continue;
    final columns = row.keys.toList()..sort();
    bool isTaken(int at) => at < entries.length && entries[at] != null;
    // Ends at the latest after everything taken so far.
    var at = nextFree(0);
    while (columns.any((column) => isTaken(at - columns.first + column))) {
      at = nextFree(at + 1);
    }
    final offset = offsets[i] = at - columns.first;
    while (entries.length <= offset + columns.last) {
      free.add(entries.length);
      entries.add(null);
    }
    row.forEach((column, value) {
      entries[offset + column] = value;
      free[offset + column] = offset + column + 1;
    });
  }
  return (offsets: offsets, entries: entries);
}

/// Which bit tells whether a class passes a test. A table has a byte for each
/// class, and so holds eight tests.
typedef TestBit = ({String table, int bit});

/// How objects are laid out and where calls on them go.
final class ObjectLayout(
  final HirModule module,
  Map<HirCallable, String> symbols,
) {
  final _classNumbers = <HirClass, int>{};
  final _fieldOffsets = <HirField, int>{};
  final _selectorOffsets = <HirSelector, int>{};
  late final List<String> _entries;

  this {
    for (final (number, class_) in module.classes.indexed) {
      _classNumbers[class_] = number;
      for (final (i, field) in class_.fields.indexed) {
        _fieldOffsets[field] = _headerBytes + i * _fieldBytes;
      }
    }
    final selectors = module.dispatch.keys.toList();
    final (:offsets, :entries) = packRows([
      for (final selector in selectors)
        {
          for (final MapEntry(key: class_, value: function)
              in module.dispatch[selector]!.entries)
            _classNumbers[class_]!: symbols[function]!,
        },
    ]);
    for (final (i, selector) in selectors.indexed) {
      _selectorOffsets[selector] = offsets[i];
    }
    _entries = [for (final entry in entries) entry ?? _holeSymbol];
  }

  /// The tables the program needs.
  List<LirTable> get tables => [
    if (module.dispatch.isNotEmpty) LirTable(_tableSymbol, _entries),
  ];

  /// The functions that [tables] need beyond the program's own.
  List<LirFunction> get functions => [
    if (_entries.contains(_holeSymbol))
      LirFunction(_holeSymbol, LirSignature([]), [
        LirBlock()..end(Unreachable()),
      ]),
  ];

  /// The bytes of an object of [class_], without its elements.
  int sizeOf(HirClass class_) => class_.elements == null
      ? _headerBytes + class_.fields.length * _fieldBytes
      : elementsOffset;

  int? numberOf(HirClass class_) => _classNumbers[class_];

  /// The allocation of an object of [class_], not yet part of [block].
  Alloc allocation(LirBlock block, HirClass class_, [LirValue? length]) {
    final size = block.add(ConstInt(sizeOf(class_)));
    if (length == null) return Alloc(size);
    final elements = class_.elements == .references
        ? block.add(IntBinary(.shl, length, block.add(ConstInt(3))))
        : length;
    return Alloc(block.add(IntBinary(.add, size, elements)));
  }

  /// Makes [object] one of [class_], with [length] elements if it has any.
  LirValue setClass(
    LirBlock block,
    LirValue object,
    HirClass class_, [
    LirValue? length,
  ]) {
    final number = block.add(ConstInt(numberOf(class_)!));
    block.add(Store(.u32, object, number, offset: classOffset));
    if (length != null) {
      block.add(Store(.i64, object, length, offset: lengthOffset));
    }
    return object;
  }

  static Width widthOf(HirType type) => switch (type) {
    .integer || .boolean => .i64,
    .float => .f64,
    .reference => .ref,
  };

  LirValue load(LirBlock block, HirField field, LirValue object) =>
      block.add(Load(widthOf(field.type), object, offset: offsetOf(field)));

  void store(LirBlock block, HirField field, LirValue object, LirValue value) =>
      block.add(
        Store(widthOf(field.type), object, value, offset: offsetOf(field)),
      );

  static Width _elementWidth(HirElement element) => switch (element) {
    .reference => .ref,
    .int8 => .i8,
    .uint8 => .u8,
    .int16 => .i16,
    .uint16 => .u16,
    .int32 => .i32,
    .uint32 => .u32,
    .int64 => .i64,
    .float32 => .f32,
    .float64 => .f64,
  };

  static LirValue _scaled(LirBlock block, HirElement element, LirValue index) =>
      element == .reference
      ? block.add(IntBinary(.shl, index, block.add(ConstInt(3))))
      : index;

  LirValue length(LirBlock block, LirValue array) =>
      block.add(Load(.i64, array, offset: lengthOffset));

  LirValue loadElement(
    LirBlock block,
    HirElement element,
    LirValue array,
    LirValue index,
  ) => block.add(
    Load(
      _elementWidth(element),
      array,
      offset: elementsOffset,
      index: _scaled(block, element, index),
    ),
  );

  void storeElement(
    LirBlock block,
    HirElement element,
    LirValue array,
    LirValue index,
    LirValue value,
  ) => block.add(
    Store(
      _elementWidth(element),
      array,
      value,
      offset: elementsOffset,
      index: _scaled(block, element, index),
    ),
  );

  /// A field of a class without objects is only used by code that never runs.
  int offsetOf(HirField field) => _fieldOffsets[field] ?? _headerBytes;

  /// Whether integers without an object can receive calls of [selector].
  bool canReceive(HirSelector selector) =>
      module.dispatch[selector]!.containsKey(module.integers);

  /// Reads whether the class with [number] passes [test].
  LirValue isInstance(LirBlock block, TestBit test, LirValue number) {
    final table = block.add(SymbolAddress(test.table));
    final byte = block.add(Load(.u8, table, index: number));
    final shifted = test.bit == 0
        ? byte
        : block.add(IntBinary(.shr, byte, block.add(ConstInt(test.bit))));
    return block.add(IntBinary(.and, shifted, block.add(ConstInt(1))));
  }

  /// The address of what the class with [number] has for [selector].
  LirValue lookUp(LirBlock block, HirSelector selector, LirValue number) {
    final row = block.add(ConstInt(_selectorOffsets[selector]!));
    final entry = block.add(IntBinary(.add, number, row));
    final index = block.add(IntBinary(.shl, entry, block.add(ConstInt(2))));
    final table = block.add(SymbolAddress(_tableSymbol));
    final distance = block.add(Load(.i32, table, index: index));
    return block.add(PtrAdd(table, distance));
  }
}
