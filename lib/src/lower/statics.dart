import 'dart:typed_data';

import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'boxes.dart';
import 'dispatch.dart';

/// The object holding the program's global variables.
const globalsSymbol = '.globals';

/// What the collector needs to know of each class.
const classTableSymbol = '.classes';

/// Where the first global variable is. References come before all others.
const firstGlobal = 8;

/// Marks objects that the collector leaves alone, after their class number.
const _fixedFlag = 4;

/// Objects that exist from the start of the program.
final class StaticData(final HirModule module, final ObjectLayout _layout) {
  final _constants = <HirConstObject, String>{};
  final _objects = <LirStatic>[];
  final _tests = <HirTypeTest, TestBit>{};
  final _testBytes = <Uint8List>[];
  final _offsets = <HirGlobal, int>{};

  late final List<HirGlobal> _globals = [
    ...module.globals.where((global) => global.type == .reference),
    ...module.globals.where((global) => global.type != .reference),
  ];

  this {
    for (final (i, global) in _globals.indexed) {
      _offsets[global] = firstGlobal + i * 8;
    }
    if (_globals.isNotEmpty || module.allocate != null) {
      final words = _Words(firstGlobal + _globals.length * 8);
      for (final global in _globals) {
        _set(words, _offsets[global]!, global.initial);
      }
      _objects.add(words.build(globalsSymbol, writable: true));
    }
  }

  /// Where it is found which classes pass [test].
  TestBit test(HirTypeTest test) => _tests.putIfAbsent(test, () {
    final passing = module.tests[test]!;
    final number = _tests.length, bit = number % 8;
    if (bit == 0) _testBytes.add(Uint8List(module.classes.length));
    final bytes = _testBytes.last;
    for (final (i, class_) in module.classes.indexed) {
      if (passing.contains(class_)) bytes[i] |= 1 << bit;
    }
    return (table: _testSymbol(number ~/ 8), bit: bit);
  });

  static String _testSymbol(int number) => '.is.$number';

  /// The tables that tests read, once the program's functions are lowered.
  List<LirData> get tables => [
    for (final (i, bytes) in _testBytes.indexed) LirData(_testSymbol(i), bytes),
  ];

  /// Every object, once the program's functions are lowered.
  List<LirStatic> get objects => _objects;

  /// The number of globals that hold references.
  int get rootCount =>
      module.globals.where((global) => global.type == .reference).length;

  int offsetOf(HirGlobal global) => _offsets[global]!;

  /// The bits of the reference that [object] is, if it is an integer that needs
  /// no object.
  int? bitsOf(HirConstObject object) => object.target == module.integers
      ? BoxLowering.bitsOf(object.fields.values.single! as int)
      : null;

  /// The symbol of [object].
  String constant(HirConstObject object) => _constants.putIfAbsent(object, () {
    final HirConstObject(:target, :fields, :elements) = object;
    final elementBytes = target.elements == .references ? 8 : 1;
    final words = _Words(
      _layout.sizeOf(target) + (elements?.length ?? 0) * elementBytes,
    );
    words.data
      ..setUint32(classOffset, _layout.numberOf(target)!, .little)
      ..setUint32(classOffset + 4, _fixedFlag, .little);
    fields.forEach((field, value) {
      _set(words, _layout.offsetOf(field), value);
    });
    if (elements != null) {
      words.data.setInt64(lengthOffset, elements.length, .little);
    }
    for (final (i, element) in (elements ?? const []).indexed) {
      if (target.elements == .references) {
        _set(words, elementsOffset + i * 8, element);
      } else {
        words.data.setUint8(elementsOffset + i, element as int);
      }
    }
    final symbol = '.const.${_constants.length}';
    // Those it refers to took their numbers already.
    _objects.add(words.build(symbol, writable: false));
    return symbol;
  });

  void _set(_Words words, int offset, Object? value) {
    switch (value) {
      case HirConstObject():
        if (bitsOf(value) case final bits?) {
          words.data.setInt64(offset, bits, .little);
        } else {
          words.references[offset] = constant(value);
        }
      case int():
        words.data.setInt64(offset, value, .little);
      case double():
        words.data.setFloat64(offset, value, .little);
      case bool():
        words.data.setInt64(offset, value ? 1 : 0, .little);
      default:
        break;
    }
  }

  /// For each class, where its record is; then each record: the number of
  /// references in fields that it keeps, its kind, their offsets, and those of
  /// other fields if it is weak.
  LirData classTable() {
    final words = <int>[], starts = <int>[];
    for (final class_ in module.classes) {
      final kept = [
        for (final field in class_.fields)
          if (field.type == .reference && !field.isWeak) field,
      ];
      starts.add((module.classes.length + words.length) * 4);
      final weakness = class_.weakness;
      final fields = [
        ...kept,
        if (weakness != null)
          for (final field in class_.fields)
            if (!kept.contains(field)) field,
      ];
      words.addAll([
        kept.length,
        weakness != null
            ? 2 + weakness.index
            : class_.elements == .references
            ? 1
            : 0,
        for (final field in fields) _layout.offsetOf(field),
      ]);
    }
    return LirData(
      classTableSymbol,
      Uint32List.fromList([...starts, ...words]).buffer.asUint8List(),
    );
  }
}

final class _Words(int bytes) {
  final ByteData data = ByteData(bytes);
  final Map<int, String> references = {};

  LirStatic build(String name, {required bool writable}) => LirStatic(
    name,
    data.buffer.asUint8List(),
    references: references,
    writable: writable,
  );
}
