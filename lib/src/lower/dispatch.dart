import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

/// Where objects store their class, as a 32-bit number.
const classOffset = 0;
const _headerBytes = 8, _fieldBytes = 8;

const _tableSymbol = '.dispatch', _holeSymbol = '.hole';

/// Overlays sparse [rows] in one list, so that entry c of row i is at its
/// offset plus c. Offsets can be negative; indexes of entries are not.
({List<int> offsets, List<T?> entries}) packRows<T extends Object>(
  List<Map<int, T>> rows,
) {
  final offsets = List.filled(rows.length, 0);
  final taken = <int, T>{};
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
    final first = row.keys.reduce((a, b) => a < b ? a : b);
    // Ends at the latest after everything taken so far.
    var offset = -first;
    while (row.keys.any((column) => taken.containsKey(offset + column))) {
      offset++;
    }
    offsets[i] = offset;
    row.forEach((column, value) => taken[offset + column] = value);
  }
  final length = taken.keys.fold(0, (end, at) => at >= end ? at + 1 : end);
  return (
    offsets: offsets,
    entries: [for (var i = 0; i < length; i++) taken[i]],
  );
}

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

  /// Creates an object of [class_].
  LirValue allocate(LirBlock block, HirClass class_) {
    final size = _headerBytes + class_.fields.length * _fieldBytes;
    final object = block.add(Alloc(block.add(ConstInt(size))));
    final number = block.add(ConstInt(_classNumbers[class_]!));
    block.add(Store(.u32, object, number, offset: classOffset));
    return object;
  }

  static Width _width(HirField field) => switch (field.type) {
    .integer || .boolean => .i64,
    .float => .f64,
    .reference => .ref,
  };

  LirValue load(LirBlock block, HirField field, LirValue object) =>
      block.add(Load(_width(field), object, offset: _offsetOf(field)));

  void store(LirBlock block, HirField field, LirValue object, LirValue value) =>
      block.add(Store(_width(field), object, value, offset: _offsetOf(field)));

  /// A field of a class without objects is only used by code that never runs.
  int _offsetOf(HirField field) => _fieldOffsets[field] ?? _headerBytes;

  /// The address of what the class of [receiver] has for [selector].
  LirValue lookUp(LirBlock block, HirSelector selector, LirValue receiver) {
    final table = block.add(SymbolAddress(_tableSymbol));
    final number = block.add(Load(.u32, receiver, offset: classOffset));
    final index = block.add(IntBinary(.shl, number, block.add(ConstInt(2))));
    final offset = block.add(
      Load(.i32, table, offset: _selectorOffsets[selector]! * 4, index: index),
    );
    return block.add(PtrAdd(table, offset));
  }
}
