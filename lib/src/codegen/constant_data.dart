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

  int typeAddress(ClassType type) => _type(
    type,
    layouts.isBoxable(type)
        ? ObjectLayout([layouts.representation(type)])
        : layouts.storageOf(type).layout,
  );

  int addressOf(Constant value) {
    if (value is TypeConstant) {
      return addressOf(layouts.types.constant(value.representedType));
    }
    final key = value.structuralKey;
    if (_constants[key] case final symbol?) return symbol;
    final ClassStorage? storage;
    final ObjectLayout layout;
    if (value is ObjectConstant) {
      storage = layouts.storageOf(value.type as ClassType);
      if (storage.errorTraceOffset != null) {
        throw UnsupportedError(
          'An Error instance cannot use immutable constant storage.',
        );
      }
      layout = storage.layout;
      if (storage.fields.length != value.fields.length ||
          storage.fields.any((f) => !value.fields.containsKey(f))) {
        throw ArgumentError(
          'Incomplete native constant storage: ${value.type}',
        );
      }
    } else if (value is ScalarConstant && layouts.isBoxable(value.type)) {
      storage = null;
      layout = .new([layouts.representation(value.type)]);
    } else {
      throw UnsupportedError('Native boxed constant: ${value.type}');
    }
    final offset = _words.length * 8;
    final symbol = _reserve('constant', layout.size ~/ 8);
    _constants[key] = symbol;
    relocations.add(
      .address(
        1,
        offset + ObjectLayout.typeOffset,
        _type(value.type as ClassType, layout),
      ),
    );
    if (storage == null) {
      _write(value, value.type, offset + layout.offsetOf(0));
    } else {
      for (final (i, field) in storage.fields.indexed) {
        _write(
          (value as ObjectConstant).fields[field]!,
          field.type,
          offset + layout.offsetOf(i),
        );
      }
    }
    return symbol;
  }

  void _write(Constant value, ValueType type, int offset) {
    layouts.checkTransfer(value.type, type, constant: value is ScalarConstant);
    if (layouts.representation(type) == .reference && value.type != .nullType) {
      relocations.add(.address(1, offset, addressOf(value)));
      return;
    }
    _words[offset ~/ 8] = switch (value) {
      ScalarConstant(value: final int number) => number,
      ScalarConstant(value: final bool flag) => flag ? 1 : 0,
      ScalarConstant(value: final double number) => (ByteData(
        8,
      )..setFloat64(0, number, .little)).getInt64(0, .little),
      ScalarConstant(value: null) => 0,
      _ => throw UnsupportedError(
        'Native object field constant: ${value.type}',
      ),
    };
  }

  int _type(ClassType type, ObjectLayout layout) {
    if (_types[type] case final symbol?) return symbol;
    final references = layout.referenceOffsets.toList();
    final tests = layouts.typeTestBits(type);
    final start = _words.length;
    final symbol = _types[type] = _reserve(
      'type',
      3 + references.length + tests.length,
    );
    _words[start] = layout.size;
    _words[start + 1] = references.length;
    _words.setRange(start + 2, start + 2 + references.length, references);
    _words[start + 2 + references.length] = layouts.isBoxable(type)
        ? 0
        : layouts.storageOf(type).errorTraceOffset ?? 0;
    _words.setRange(start + 3 + references.length, _words.length, tests);
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
