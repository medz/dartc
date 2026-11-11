import 'dart:typed_data';

import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

import 'program_layout.dart';
import 'list_storage.dart';

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
    final list =
        value is SequenceConstant &&
            (value.type as ClassType).declaration == CoreTypes.list
        ? value
        : null;
    final carrier = value is FunctionConstant
        ? layouts.closures.constants[value.structuralKey]!
        : null;
    if (carrier != null) {
      storage = layouts.storageOf(carrier.type);
      layout = storage.layout;
    } else if (list != null) {
      storage = layouts.storageOf(layouts.lists.type);
      layout = storage.layout;
    } else if (value is ObjectConstant) {
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
    } else if (value is ScalarConstant && value.type == ValueType.string) {
      storage = null;
      layout = layouts.storageOf(ValueType.string).layout;
    } else if (value is ScalarConstant && layouts.isBoxable(value.type)) {
      storage = null;
      layout = .new([layouts.representation(value.type)]);
    } else {
      throw UnsupportedError('Native boxed constant: ${value.type}');
    }
    final offset = _words.length * 8;
    final payloadWords = switch (value) {
      ScalarConstant(value: final String text) => (text.length + 3) ~/ 4,
      _ => 0,
    };
    final size = layout.size + payloadWords * 8;
    final symbol = _reserve('constant', size ~/ 8);
    _constants[key] = symbol;
    final type =
        carrier?.type ??
        (list == null
            ? value.type as ClassType
            : layouts.lists.type.instantiate(
                (list.type as ClassType).typeArguments,
              ));
    _header(symbol, offset, type, layout, size, carrier?.signature ?? type);
    if (list != null) {
      _words[(offset + layouts.fieldOffset(layouts.lists.mutability)) ~/ 8] =
          ListMutability.immutable.index;
      _words[(offset + layouts.fieldOffset(layouts.lists.length)) ~/ 8] =
          list.elements.length;
      relocations.add(
        .address(
          1,
          offset + layouts.fieldOffset(layouts.lists.data),
          _listData(list.elements),
        ),
      );
    } else if (carrier != null) {
      _write(
        Constant.integer(carrier.tag),
        .integer,
        offset + layout.offsetOf(0),
      );
    } else if (value case ScalarConstant(value: final String text)) {
      _words[(offset + layouts.fieldOffset(layouts.strings.length)) ~/ 8] =
          text.length;
      final start = (offset + layout.size) ~/ 8;
      for (var i = 0; i < text.length; i++) {
        _words[start + i ~/ 4] |= text.codeUnitAt(i) << ((i % 4) * 16);
      }
    } else if (storage == null) {
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

  void _header(
    int symbol,
    int offset,
    ClassType type,
    ObjectLayout layout,
    int size,
    ValueType runtimeType,
  ) {
    _words[(offset + ObjectLayout.sizeOffset) ~/ 8] = size;
    _words[(offset + ObjectLayout.identityHashOffset) ~/ 8] =
        ((symbol + 1) * 0x9e3779b9) & 0x3fffffff;
    relocations.add(
      .address(1, offset + ObjectLayout.descriptorOffset, _type(type, layout)),
    );
    relocations.add(
      .address(
        1,
        offset + ObjectLayout.typeOffset,
        addressOf(layouts.types.constant(runtimeType)),
      ),
    );
  }

  int _listData(List<Constant> elements) {
    final type = layouts.lists.buffer, layout = layouts.storageOf(type).layout;
    final offset = _words.length * 8, size = layout.size + elements.length * 8;
    final symbol = _reserve('list-data', size ~/ 8);
    _header(symbol, offset, type, layout, size, type);
    for (final (i, element) in elements.indexed) {
      _write(element, .object.nullable, offset + layout.size + i * 8);
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
    final start = _words.length;
    final symbol = _types[type] = _reserve('type', 4 + references.length);
    _words[start] = layout.size;
    _words[start + 1] = references.length;
    _words.setRange(start + 2, start + 2 + references.length, references);
    _words[start + 2 + references.length] = layouts.isBoxable(type)
        ? 0
        : layouts.storageOf(type).errorTraceOffset ?? 0;
    _words[start + 3 + references.length] = layout.tracesPayload
        ? layout.size
        : 0;
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
