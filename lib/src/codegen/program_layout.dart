import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'type_values.dart';
import 'instance_storage.dart';
import 'type_relations.dart';

enum TypeTestKind() {
  constantTrue,
  constantFalse,
  isNull,
  isNotNull,
  subtype,
}

/// Assigns physical storage to declaration identities within one compilation.
final class ProgramLayout(
  Iterable<IrClass> classes, {
  Iterable<ClassType> referencedClasses = const [],
  InstanceStorage? instanceStorage,
}) {
  final instances = instanceStorage ?? InstanceStorage([]);
  final types = TypeValues();
  late final TypeRelations relations;
  final _classes = {
    for (final declaration in classes) declaration.type: declaration,
  };
  final _storage = <ClassType, ClassStorage>{};

  this {
    for (final declaration in types.classes) {
      _classes[declaration.type] = declaration;
    }
    relations = TypeRelations(types, [..._classes.keys, ...referencedClasses]);
    for (final declaration in relations.classes) {
      _classes[declaration.type] = declaration;
    }
  }

  TypeTestKind typeTest(ValueType source, ValueType tested) {
    if (FfiTypes.isPointer(source)) source = FfiTypes.pointerRuntimeType;
    if (tested.accepts(source)) return .constantTrue;
    if (tested == .never ||
        source == .nullType && !tested.mayBeNull ||
        tested == .nullType && !source.mayBeNull ||
        tested.freeTypeParameters.isEmpty &&
            (isBoxable(source) || FfiTypes.isPointer(source))) {
      return .constantFalse;
    }
    if (tested == .nullType) return .isNull;
    if (tested == .object ||
        !tested.mayBeNull && tested.accepts(source.nonNullable)) {
      return .isNotNull;
    }
    return .subtype;
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

  /// Appends factory owner and function type arguments to Dart parameters.
  List<ValueType> entryTypes(FunctionTarget target) =>
      target.typeParameters.isEmpty &&
          !(target.kind == .factory && target.owner!.typeParameters.isNotEmpty)
      ? target.parameterTypes
      : [
          ...target.parameterTypes,
          if (target.kind == .factory &&
              target.owner!.typeParameters.isNotEmpty)
            TypeValues.type,
          for (final _ in target.typeParameters) TypeValues.type,
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
      'Native representation conversion: ${source.dartName} to ${destination.dartName}',
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
        for (final field in definition.fields)
          if (field.isLate) ...[
            instances.slots(field).$1,
            instances.slots(field).$2,
          ] else
            field,
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
      storageOf(field.owner)
          .offsetOf(field.isLate ? instances.slots(field).$1 : field);
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
    errorTraceOffset = storesErrorTrace
        ? ObjectLayout.fieldsOffset +
              this.fields.length * ObjectLayout.alignment
        : null;
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
