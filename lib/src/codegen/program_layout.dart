import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Assigns physical storage to declaration identities within one compilation.
final class ProgramLayout(Iterable<IrClass> classes) {
  static final typeValue = ClassType(
    Uri.parse('dartc:types'),
    '_Type',
    interfaces: [ValueType.typeType],
  );
  final _classes = {
    typeValue: IrClass(typeValue, []),
    for (final declaration in classes) declaration.type: declaration,
  };
  final _storage = <ClassType, ClassStorage>{};
  final _typeTests = <ValueType, int>{};
  bool _typesWritten = false;

  int typeTest(ValueType type) {
    if (type.freeTypeParameters.isNotEmpty) {
      throw UnsupportedError(
        'Native type test requires a type environment: $type',
      );
    }
    if (_typeTests[type] case final index?) return index;
    if (_typesWritten) {
      throw StateError('Type tests must precede descriptor emission.');
    }
    return _typeTests[type] = _typeTests.length;
  }

  List<int> typeTestBits(ClassType type) {
    if (type.freeTypeParameters.isNotEmpty) {
      throw UnsupportedError(
        'Native object type requires a type environment: $type',
      );
    }
    _typesWritten = true;
    // shortcut: module-local closed types, reify environments before open generics or managed cross-module calls.
    final words = List.filled((_typeTests.length + 63) ~/ 64, 0);
    for (final MapEntry(key: tested, value: index) in _typeTests.entries) {
      if (tested.accepts(type)) words[index ~/ 64] |= 1 << (index % 64);
    }
    return words;
  }

  ValueRepresentation representation(ValueType type) {
    if (type == .integer || type == .boolean) return .word;
    if (type == .floating) return .floating;
    if (FfiTypes.isPointer(type)) return .address;
    if (type is CellType || type == .voidType || type == .never) {
      throw UnsupportedError('Native value representation: $type');
    }
    return .reference;
  }

  NativeTypeRef callType(ValueType type) {
    if (type == .voidType || type == .never) return NativeScalarType(Void);
    // Internal references occupy pointer locations without becoming FFI values.
    return switch (representation(type)) {
      .word => NativeScalarType(Int64),
      .floating => NativeScalarType(Double),
      .address || .reference => NativePointerType(NativeScalarType(Void)),
    };
  }

  /// Appends reified function type arguments to the declared Dart parameters.
  List<ValueType> entryTypes(FunctionTarget target) =>
      target.typeParameters.isEmpty
      ? target.parameterTypes
      : [
          ...target.parameterTypes,
          for (final _ in target.typeParameters) ValueType.typeType,
        ];

  /// Checks transfers before a machine word loses its semantic type.
  void checkTransfer(
    ValueType source,
    ValueType destination, {
    bool constant = false,
  }) {
    final from = representation(source), to = representation(destination);
    // IR proves assignment or generic substitution; checked casts are separate.
    if (from == to ||
        from == .reference && isBoxable(destination) ||
        to == .reference &&
            (source == .boolean || constant && isBoxable(source))) {
      return;
    }
    throw UnsupportedError(
      'Native representation conversion: $source to $destination',
    );
  }

  bool isBoxable(ValueType type) =>
      type == .integer || type == .boolean || type == .floating;

  /// Whether the value or local contents are traced by a managed collector.
  bool isReference(ValueType type) =>
      representation(type is CellType ? type.content : type) == .reference;

  ClassStorage storageOf(ClassType type) {
    final declaration = type.declaration;
    if (_storage[declaration] case final known?) return known;
    if (declaration == ValueType.object) {
      return _storage[declaration] = ClassStorage([], this);
    }
    final definition = _classes[declaration];
    if (definition == null) {
      throw UnsupportedError('Native class storage unavailable: $declaration');
    }
    return _storage[declaration] = ClassStorage(
      [
        if (declaration.superclass case final parent?)
          ...storageOf(parent).fields,
        ...definition.fields,
      ],
      this,
      storesErrorTrace:
          declaration == ValueType.error ||
          switch (declaration.superclass) {
            null => false,
            final parent => storageOf(parent).errorTraceOffset != null,
          },
    );
  }

  int fieldOffset(InstanceField field) =>
      storageOf(field.owner).offsetOf(field);
}

/// Declared field identities paired with their shared physical layout.
final class ClassStorage(
  Iterable<InstanceField> fields,
  ProgramLayout program, {
  bool storesErrorTrace = false,
}) {
  final List<InstanceField> fields = .unmodifiable(fields);
  late final ObjectLayout layout;
  late final int? errorTraceOffset;

  this {
    errorTraceOffset = storesErrorTrace ? (this.fields.length + 1) * 8 : null;
    layout = .new([
      ...this.fields.map((f) => program.representation(f.type)),
      if (storesErrorTrace) ValueRepresentation.reference,
    ]);
  }

  int offsetOf(InstanceField field) {
    final index = fields.indexOf(field);
    if (index < 0) {
      throw ArgumentError('Undeclared native field: ${field.name}');
    }
    return layout.offsetOf(index);
  }
}
