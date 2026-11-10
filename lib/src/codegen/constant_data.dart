import 'dart:typed_data';

import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

import 'program_layout.dart';

/// Writes canonical constant objects and their concrete type descriptors.
final class ConstantData(final ProgramLayout layouts, final int symbolBase) {
  final symbols = <Symbol>[];
  final relocations = <Relocation>[];
  final _words = <int>[];
  final _constants = <Object, int>{};
  final _types = <ClassType, int>{};

  int addressOf(ObjectConstant value) {
    final key = value.structuralKey;
    if (_constants[key] case final symbol?) return symbol;
    final type = value.type as ClassType, storage = layouts.storageOf(type);
    if (storage.fields.length != value.fields.length ||
        storage.fields.any((f) => !value.fields.containsKey(f))) {
      throw ArgumentError('Incomplete native constant storage: $type');
    }
    final offset = _words.length * 8;
    final symbol = _reserve('constant', storage.layout.size ~/ 8);
    _constants[key] = symbol;
    relocations.add(
      .address(
        1,
        offset + ObjectLayout.typeOffset,
        _type(type, storage.layout),
      ),
    );
    for (final (i, field) in storage.fields.indexed) {
      final constant = value.fields[field]!;
      layouts.checkTransfer(constant.type, field.type);
      final position = offset + storage.layout.offsetOf(i);
      switch (constant) {
        case final ObjectConstant object:
          relocations.add(.address(1, position, addressOf(object)));
        case ScalarConstant(:final value):
          _words[position ~/ 8] = switch (value) {
            int() => value,
            bool() => value ? 1 : 0,
            double() => (ByteData(
              8,
            )..setFloat64(0, value, .little)).getInt64(0, .little),
            null => 0,
            _ => throw UnsupportedError(
              'Native object field constant: ${constant.type}',
            ),
          };
        default:
          throw UnsupportedError(
            'Native object field constant: ${constant.type}',
          );
      }
    }
    return symbol;
  }

  int _type(ClassType type, ObjectLayout layout) {
    if (_types[type] case final symbol?) return symbol;
    final references = layout.referenceOffsets.toList();
    final start = _words.length;
    final symbol = _types[type] = _reserve('type', 2 + references.length);
    _words[start] = layout.size;
    _words[start + 1] = references.length;
    _words.setRange(start + 2, _words.length, references);
    return symbol;
  }

  int _reserve(String name, int words) {
    final symbol = symbolBase + symbols.length;
    symbols.add(
      .new(
        '$name$symbol',
        1,
        _words.length * 8,
        words * 8,
        kind: .data,
        binding: .local,
      ),
    );
    _words.addAll(List.filled(words, 0));
    return symbol;
  }

  Section finish() {
    final data = ByteData(_words.length * 8);
    for (final (i, word) in _words.indexed) {
      data.setInt64(i * 8, word, .little);
    }
    return .readOnlyData(
      data.buffer.asUint8List(),
      alignment: ObjectLayout.alignment,
    );
  }
}
