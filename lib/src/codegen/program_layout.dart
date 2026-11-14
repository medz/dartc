import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'closure_storage.dart';
import 'type_values.dart';
import 'type_runtime.dart';
import 'instance_storage.dart';
import 'type_relations.dart';
import 'pointer_storage.dart';
import 'native_storage.dart';
import 'native_calls.dart';

import 'package:dartc/abi.dart' show NativeLayout;

import 'pointer_representation.dart';
import 'string_storage.dart';
import 'list_storage.dart';
import 'record_storage.dart';

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
  Iterable<IrFunction> functions = const [],
  Iterable<ClassType>? referencedClasses,
  NativeLayout? nativeLayout,
  InstanceStorage? instanceStorage,
  ClosureStorage? closureStorage,
  StringStorage? stringStorage,
  ListStorage? listStorage,
  RecordStorage? recordStorage,
  TypeRuntime? typeRuntime,
}) {
  final instances = instanceStorage ?? InstanceStorage([]);
  final closures = closureStorage ?? ClosureStorage([]);
  final types = TypeValues(typeRuntime);
  final pointers = PointerStorage();
  final nativeCalls = NativeCalls();
  final NativeStorage? native = nativeLayout == null
      ? null
      : NativeStorage(nativeLayout);
  final pointerRepresentation = PointerRepresentation(functions);
  final strings = stringStorage ?? StringStorage();
  final lists = listStorage ?? ListStorage(classes);
  final records = recordStorage ?? RecordStorage(classes, const []);
  late final TypeRelations relations;
  final _classes = {
    for (final declaration in classes) declaration.type: declaration,
  };
  final _storage = <ClassType, ClassStorage>{};

  /// Completes generated storage before any offsets or descriptors are consumed.
  void defineStorage(IrClass declaration) {
    if (_storage.containsKey(declaration.type)) {
      throw StateError('Class storage was already consumed.');
    }
    _classes[declaration.type] = declaration;
  }

  this {
    _classes[FfiTypes.pointer] = pointers.declaration;
    _classes[ValueType.string] = strings.declaration;
    for (final declaration in types.classes) {
      _classes.putIfAbsent(declaration.type, () => declaration);
    }
    relations = TypeRelations(
      types,
      referencedClasses ?? _classes.keys,
      recordStorage: records.declaration?.type,
    );
  }

  FunctionTarget collectionFactory(ClassType type) =>
      _classes[type.declaration]?.constructors['new'] ??
      (throw ArgumentError(
        'Collection construction requires the checked SDK factory: ${type.name}',
      ));

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
    return .reference;
  }

  NativeTypeRef callType(ValueType type) {
    // Dart void carries a value; native Void belongs only to FFI boundaries.
    return switch (representation(type)) {
      .word => NativeScalarType(Int64),
      .floating => NativeScalarType(Double),
      .address || .reference => NativePointerType(NativeScalarType(Void)),
    };
  }

  /// Selects parameter storage and appends lexical type arguments.
  List<ValueType> entryTypes(FunctionTarget target) => [
    for (final (i, type) in target.parameterTypes.indexed)
      pointerRepresentation.contains(target, i) ? .integer : type,
    if (target.kind == .factory && target.owner!.typeParameters.isNotEmpty)
      TypeMetadata.type,
    for (final _ in target.typeParameters) TypeMetadata.type,
  ];

  /// The physical return value shared by callees and every selected caller.
  ValueType returnType(FunctionTarget target) =>
      pointerRepresentation.returnsAddress(target)
      ? .integer
      : target.returnType;

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

  /// Whether the physical value is traced; stack cells supply their content type.
  bool isReference(ValueType type) => representation(type) == .reference;

  ClassStorage storageOf(ClassType type) {
    final declaration = type.declaration;
    if (_storage[declaration] case final known?) return known;
    if (FfiTypes.isCompound(declaration)) {
      final view = native!.view(declaration);
      return _storage[declaration] = ClassStorage(view.fields, this);
    }
    if (declaration == native?.buffer) {
      return _storage[declaration] = ClassStorage([], this);
    }
    if (declaration == ValueType.object) {
      return _storage[declaration] = ClassStorage([], this);
    }
    final definition = _classes[declaration];
    if (definition == null) {
      throw UnsupportedError(
        'Native class storage unavailable: ${declaration.library}::${declaration.name}',
      );
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
      tracesPayload: definition.referencePayload,
      weakFields: {
        if (declaration.superclass case final parent?)
          ...storageOf(parent).weakFields,
        ...definition.weakFields,
      },
      ephemerons: {
        if (declaration.superclass case final parent?)
          ...storageOf(parent).ephemerons,
        ...definition.ephemerons,
      },
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
  bool tracesPayload = false,
  final Set<InstanceField> weakFields = const {},
  final Map<InstanceField, InstanceField> ephemerons = const {},
}) {
  final List<InstanceField> fields = .unmodifiable(fields);
  late final ObjectLayout layout;
  late final int? errorTraceOffset;

  this {
    errorTraceOffset = storesErrorTrace
        ? ObjectHeader.fieldsOffset +
              this.fields.length * ObjectHeader.alignment
        : null;
    layout = .new(
      [
        ...this.fields.map((f) => program.representation(f.type)),
        if (storesErrorTrace) ValueRepresentation.reference,
      ],
      tracesPayload: tracesPayload,
      weakFields: weakFields.map(this.fields.indexOf),
      ephemerons: {
        for (final pair in ephemerons.entries)
          this.fields.indexOf(pair.key): this.fields.indexOf(pair.value),
      },
    );
  }

  int offsetOf(InstanceField field) {
    final index = fields.indexOf(field);
    if (index < 0) {
      throw ArgumentError('Undeclared native field: ${field.name}');
    }
    return layout.offsetOf(index);
  }
}
