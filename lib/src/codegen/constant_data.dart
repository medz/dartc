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
  final ClassType? stackContext,
  final Map<FunctionTarget, int> functionSymbols = const {},
}) {
  final symbols = <Symbol>[];
  final relocations = <Relocation>[];
  final _words = <int>[];
  final _constants = <Object, int>{};
  final _types = <ClassType, int>{};
  final _frames = <Object, int>{};
  final _callableTables = <FunctionTarget, int?>{};

  /// Binds only actual executable entries; identity-only storage has no table.
  int? callableTable(FunctionTarget target) =>
      _callableTables.putIfAbsent(target, () {
        final entries = {
          for (final entry
              in layouts.closures.implementations.entriesFor(target).entries)
            entry.key.slot: ?functionSymbols[entry.value],
        };
        if (entries.isEmpty) return null;
        final size = entries.keys.reduce((a, b) => a > b ? a : b) + 1;
        final offset = _words.length * 8;
        final symbol = _reserve('callableEntries', size);
        for (final entry in entries.entries) {
          relocations.add(.address(1, offset + entry.key * 8, entry.value));
        }
        return symbol;
      });
  final _moduleObjects =
      <
        ModuleObject,
        ({Uint8List bytes, List<({int offset, int symbol})> references})
      >{};

  /// Encodes mutable module storage using the same headers and field layout.
  ///
  /// Call before [finish] and before consuming [symbols]: descriptors, runtime
  /// types and initial reference constants may add read-only dependencies.
  /// Reference offsets are relative to this object's bytes; the caller assigns
  /// its writable section and distinct symbol without content canonicalization.
  ({Uint8List bytes, List<({int offset, int symbol})> references})
  moduleObjectData(ModuleObject declaration) => _moduleObjects.putIfAbsent(
    declaration,
    () {
      if (!layouts.isReference(declaration.type)) {
        throw ArgumentError('Module objects require reference representation.');
      }
      final storage = layouts.storageOf(declaration.type);
      final layout = storage.layout;
      if (layout.tracesPayload) {
        throw ArgumentError('Module objects require fixed-size storage.');
      }
      final bytes = ByteData(layout.size);
      final references = <({int offset, int symbol})>[];
      void word(int offset, int value) =>
          bytes.setInt64(offset, value, Endian.little);
      void reference(int offset, int symbol) =>
          references.add((offset: offset, symbol: symbol));
      _header(
        _moduleObjects.length,
        0,
        declaration.type,
        layout,
        layout.size,
        declaration.type,
        word: word,
        reference: reference,
      );
      for (final MapEntry(key: field, value: initial)
          in declaration.initialFields.entries) {
        final effective = field.isLate
            ? layouts.instances.slots(field).$1
            : field;
        if (!storage.fields.contains(effective)) {
          throw ArgumentError('Module initial binding has no physical field.');
        }
        _write(
          initial,
          effective.type,
          storage.offsetOf(effective),
          shape: layouts.slotShape(effective),
          word: word,
          reference: reference,
        );
        if (field.isLate) {
          word(storage.offsetOf(layouts.instances.slots(field).$2), 1);
        }
      }
      return (
        bytes: bytes.buffer.asUint8List().asUnmodifiableView(),
        references: List.unmodifiable(references),
      );
    },
  );

  /// Shares source names, URIs and logical caller chains across safepoints.
  int? frameAddress(FunctionTarget function, [SourceLocation? location]) {
    int? caller;
    for (final (name, source) in sourceFrames(
      function,
      location,
    ).toList().reversed) {
      final position = source?.position;
      final key = (name, position, caller);
      if (_frames[key] case final existing?) {
        caller = existing;
        continue;
      }
      final offset = _words.length * 8;
      final symbol = _reserve('frame', SourceFrameMetadata.size ~/ 8);
      _frames[key] = symbol;
      relocations.add(
        .address(
          1,
          offset + SourceFrameMetadata.name,
          addressOf(Constant.string(name)),
        ),
      );
      if (position != null) {
        relocations.add(
          .address(
            1,
            offset + SourceFrameMetadata.uri,
            addressOf(Constant.string(position.uri.toString())),
          ),
        );
        _words[(offset + SourceFrameMetadata.line) ~/ 8] = position.line;
        _words[(offset + SourceFrameMetadata.column) ~/ 8] = position.column;
      }
      if (caller != null) {
        relocations.add(
          .address(1, offset + SourceFrameMetadata.caller, caller),
        );
      }
      caller = symbol;
    }
    return caller;
  }

  int typeAddress(ClassType type) => _type(type, layouts.objectLayout(type));

  int addressOf(Constant value) {
    if (value is TypeConstant) {
      return addressOf(layouts.typeConstant(value));
    }
    final key = value.structuralKey;
    if (_constants[key] case final symbol?) return symbol;
    final ClassStorage? storage;
    final ObjectLayout layout;
    final carrier = value is FunctionConstant
        ? () {
            final existing = layouts.closures.classes.toSet();
            final shape = layouts.closures.ensureConstant(value);
            for (final declaration in layouts.closures.classes) {
              if (!existing.contains(declaration)) {
                layouts.defineStorage(declaration);
              }
            }
            return shape;
          }()
        : null;
    if (carrier != null) {
      storage = layouts.storageOf(carrier.type);
      layout = storage.layout;
    } else if (value is RecordConstant) {
      storage = layouts.storageOf(layouts.records.type);
      layout = storage.layout;
    } else if (value is ObjectConstant) {
      storage = layouts.storageOf(value.type as ClassType);
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
      ObjectConstant(:final payload) => payload.length,
      _ => 0,
    };
    final size = layout.size + payloadWords * 8;
    final symbol = _reserve('constant', size ~/ 8);
    _constants[key] = symbol;
    final type =
        carrier?.type ??
        (value is RecordConstant
            ? layouts.records.type
            : value.type as ClassType);
    _header(symbol, offset, type, layout, size, value.runtimeValueType);
    if (value is RecordConstant) {
      for (final (i, field) in value.fields.indexed) {
        _write(field, .object.nullable, offset + layout.size + i * 8);
      }
    } else if (carrier != null) {
      for (final field in FunctionStorage.fields) {
        final initial = layouts.callableConstantField(
          value as FunctionConstant,
          field,
        );
        switch (initial) {
          case FunctionEntryTableAddress(:final target):
            if (callableTable(target) case final table?) {
              relocations.add(
                .address(1, offset + storage!.offsetOf(field), table),
              );
            }
          case final Constant constant:
            _write(
              constant,
              field.type,
              offset + storage!.offsetOf(field),
              shape: layouts.slotShape(field),
            );
          default:
            throw StateError('Missing constant function storage field.');
        }
      }
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
          shape: layouts.slotShape(field),
        );
      }
    }
    if (value is ObjectConstant) {
      if (value.payload.isNotEmpty && !layout.tracesPayload) {
        throw ArgumentError('Constant payload requires traced storage.');
      }
      for (final (i, element) in value.payload.indexed) {
        _write(element, .object.nullable, offset + layout.size + i * 8);
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
    ValueType runtimeType, {
    void Function(int offset, int value)? word,
    void Function(int offset, int symbol)? reference,
  }) {
    word ??= (offset, value) => _words[offset ~/ 8] = value;
    reference ??= (offset, symbol) =>
        relocations.add(.address(1, offset, symbol));
    word(offset + ObjectHeader.sizeOffset, size);
    word(
      offset + ObjectHeader.identityHashOffset,
      ((symbol + 1) * 0x9e3779b9) & 0x3fffffff,
    );
    reference(offset + ObjectHeader.descriptorOffset, _type(type, layout));
    reference(
      offset + ObjectHeader.typeOffset,
      addressOf(layouts.types.constant(runtimeType)),
    );
  }

  void _write(
    Constant value,
    ValueType type,
    int offset, {
    ExecutionShape? shape,
    void Function(int offset, int value)? word,
    void Function(int offset, int symbol)? reference,
  }) {
    final storage = shape ?? ExecutionShapes.forType(type);
    if (!storage.isReference) {
      layouts.checkShapeTransfer(ExecutionShapes.forType(value.type), storage);
    }
    if (storage.isReference && value.type != .nullType) {
      if (reference == null) {
        relocations.add(.address(1, offset, addressOf(value)));
      } else {
        reference(offset, addressOf(value));
      }
      return;
    }
    final encoded = switch (value) {
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
    if (word == null) {
      _words[offset ~/ 8] = encoded;
    } else {
      word(offset, encoded);
    }
  }

  int _type(ClassType type, ObjectLayout layout) {
    if (_types[type] case final symbol?) return symbol;
    final words = layout.descriptorWords;
    final references = words[ObjectDescriptor.referenceCount]!;
    final start = _words.length;
    final symbol = _types[type] = _reserve('type', words.length);
    _words.setRange(
      start,
      start + words.length,
      words.map((word) => word ?? 0),
    );
    if (stackTraces) {
      final closure = layouts.closures.all
          .where((shape) => shape.type == type)
          .firstOrNull;
      final wrapper = layouts.closures.instantiatedStorage;
      final instantiated = wrapper?.type == type ? wrapper : null;
      if (closure != null || instantiated != null) {
        final metadataStart = _words.length;
        final metadata = _reserve(
          'closure.trace',
          ClosureTraceMetadata.size ~/ 8,
        );
        relocations.add(
          .address(
            1,
            (start + ObjectDescriptor.asyncBase + references) * 8,
            metadata,
          ),
        );
        final description = closure == null
            ? null
            : frameAddress(
                closure.sourceTarget,
                closure.sourceTarget.declarationLocation,
              );
        if (description != null) {
          relocations.add(
            .address(
              1,
              metadataStart * 8 + ClosureTraceMetadata.description,
              description,
            ),
          );
        }
        final field =
            instantiated?.origin ??
            (closure!.target.kind.isVirtual &&
                    stackContext != null &&
                    closure.target.owner!.asInstanceOf(stackContext!) != null
                ? closure.captures.first
                : closure.target.awaiterCapture == null
                ? null
                : closure.captures[closure.target.awaiterCapture!]);
        if (field != null && layouts.slotShape(field).hasReferences) {
          var link = layouts.fieldOffset(field), value = 0, bound = 0;
          if (closure?.target.awaiterCapture case final int index) {
            if (closure!.target.captures[index] case final CellType type) {
              final cell = layouts.cellStorageOf(type);
              if (layouts.slotShape(cell.value).hasReferences) {
                value = layouts.fieldOffset(cell.value);
                if (cell.bound case final boundField?) {
                  bound = layouts.fieldOffset(boundField);
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
