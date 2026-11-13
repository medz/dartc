import 'dart:typed_data';

import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

import 'program_layout.dart';
import 'frame_description.dart';

/// Writes canonical constant objects and their concrete type descriptors.
final class ConstantData(
  final ProgramLayout layouts,
  final int symbolBase, {
  final bool stackTraces = false,
}) {
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
    } else if (value is RecordConstant) {
      storage = layouts.storageOf(layouts.records.type);
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
      RecordConstant(:final fields) => fields.length,
      _ => 0,
    };
    final size = layout.size + payloadWords * 8;
    final symbol = _reserve('constant', size ~/ 8);
    _constants[key] = symbol;
    final type =
        carrier?.type ??
        (value is RecordConstant
            ? layouts.records.type
            : list == null
            ? value.type as ClassType
            : layouts.lists.type.instantiate(
                (list.type as ClassType).typeArguments,
              ));
    _header(
      symbol,
      offset,
      type,
      layout,
      size,
      value is RecordConstant ? _recordType(value) : carrier?.signature ?? type,
    );
    if (value is RecordConstant) {
      for (final (i, field) in value.fields.indexed) {
        _write(field, .object.nullable, offset + layout.size + i * 8);
      }
    } else if (list != null) {
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

  RecordType _recordType(RecordConstant record) {
    ValueType actual(Constant field) => switch (field) {
      RecordConstant() => _recordType(field),
      FunctionConstant() =>
        layouts.closures.constants[field.structuralKey]!.signature,
      SequenceConstant()
          when (field.type as ClassType).declaration == CoreTypes.list =>
        layouts.lists.type.instantiate((field.type as ClassType).typeArguments),
      TypeConstant() => TypeMetadata.type,
      _ => field.type,
    };
    final type = record.type as RecordType;
    return RecordType(record.fields.take(type.positionalCount).map(actual), {
      for (final entry in type.slots.entries.skip(type.positionalCount))
        entry.key: actual(record.fields[entry.value]),
    });
  }

  void _header(
    int symbol,
    int offset,
    ClassType type,
    ObjectLayout layout,
    int size,
    ValueType runtimeType,
  ) {
    _words[(offset + ObjectHeader.sizeOffset) ~/ 8] = size;
    _words[(offset + ObjectHeader.identityHashOffset) ~/ 8] =
        ((symbol + 1) * 0x9e3779b9) & 0x3fffffff;
    relocations.add(
      .address(1, offset + ObjectHeader.descriptorOffset, _type(type, layout)),
    );
    relocations.add(
      .address(
        1,
        offset + ObjectHeader.typeOffset,
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
    final weak = layout.weakFields.map(layout.offsetOf).toList();
    final conditional = [
      for (final pair in layout.ephemerons.entries) ...[
        layout.offsetOf(pair.key),
        layout.offsetOf(pair.value),
      ],
    ];
    final start = _words.length;
    final symbol = _types[type] = _reserve(
      'type',
      ObjectDescriptor.baseWords +
          references.length +
          weak.length +
          conditional.length,
    );
    _words[start + ObjectDescriptor.size] = layout.size;
    _words[start + ObjectDescriptor.referenceCount] = references.length;
    _words.setRange(
      start + ObjectDescriptor.references,
      start + ObjectDescriptor.references + references.length,
      references,
    );
    _words[start +
        ObjectDescriptor.traceBase +
        references.length] = layouts.isBoxable(type)
        ? 0
        : layouts.storageOf(type).errorTraceOffset ?? 0;
    _words[start + ObjectDescriptor.payloadBase + references.length] =
        layout.tracesPayload ? layout.size : 0;
    _words[start + ObjectDescriptor.weakCountBase + references.length] =
        weak.length;
    _words[start + ObjectDescriptor.ephemeronCountBase + references.length] =
        layout.ephemerons.length;
    if (stackTraces) {
      final closure = layouts.closures.all
          .where((shape) => shape.type == type)
          .firstOrNull;
      if (closure != null) {
        final metadataStart = _words.length;
        final metadata = _reserve(
          'closure.trace',
          ClosureTraceMetadata.size ~/ 8,
        );
        relocations.add(
          .address(
            1,
            (start + ObjectDescriptor.asyncBase + references.length) * 8,
            metadata,
          ),
        );
        // shortcut: pending callbacks have names only, add declaration spans for positions.
        final description = frameDescription(closure.target);
        if (description != null) {
          relocations.add(
            .address(
              1,
              metadataStart * 8 + ClosureTraceMetadata.description,
              addressOf(Constant.string(description)),
            ),
          );
        }
        final field =
            closure.instantiation?.origin ??
            (closure.target.kind.isVirtual
                ? closure.captures.first
                : closure.target.awaiterCapture == null
                ? null
                : closure.captures[closure.target.awaiterCapture!]);
        if (field != null && layouts.isReference(field.type)) {
          var link = layouts.fieldOffset(field), value = 0, bound = 0;
          if ((closure.instantiation, closure.target.awaiterCapture) case (
            null,
            final int index,
          )) {
            if (closure.target.captures[index] case final CellType type) {
              final cell = layouts.closures.cell(type);
              if (layouts.isReference(cell.value.type)) {
                value = layouts.fieldOffset(cell.value);
                if (cell.lazy case final lazy?) {
                  bound = layouts.fieldOffset(lazy.bound);
                }
              } else {
                link = 0;
              }
            }
          }
          _words[metadataStart + ClosureTraceMetadata.link ~/ 8] = link;
          _words[metadataStart + ClosureTraceMetadata.value ~/ 8] = value;
          _words[metadataStart + ClosureTraceMetadata.bound ~/ 8] = bound;
        }
      }
    }
    final extra = start + ObjectDescriptor.baseWords + references.length;
    _words.setRange(extra, extra + weak.length, weak);
    _words.setRange(
      extra + weak.length,
      extra + weak.length + conditional.length,
      conditional,
    );
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
      alignment: ObjectHeader.alignment,
    );
  }
}
