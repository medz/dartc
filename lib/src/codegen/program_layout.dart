import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart'
    show FlowMemoryLayout, FlowFieldLayout, FlowTypeLayout, FlowCallableLayout;
import 'package:dartc/layout.dart';

import 'closure_storage.dart';
import 'type_values.dart';
import 'type_runtime.dart';
import 'instance_storage.dart';
import 'type_relations.dart';
import 'type_implementations.dart';
import 'pointer_storage.dart';
import 'native_views.dart';
import 'native_calls.dart';

import 'package:dartc/abi.dart' show NativeLayout;

import 'pointer_representation.dart';
import 'string_storage.dart';
import 'record_storage.dart';
import 'value_carrier.dart';
import 'type_environment.dart';

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
  @override required final NativeLayout nativeLayout,
  InstanceStorage? instanceStorage,
  ClosureStorage? closureStorage,
  StringStorage? stringStorage,
  RecordStorage? recordStorage,
  TypeRuntime? typeRuntime,
  TypeImplementations? typeImplementations,
  TypeEnvironment? typeEnvironment,
  ExecutionShapes? executionShapes,
  NativeViews? nativeViews,
}) implements FlowMemoryLayout, FlowFieldLayout, FlowTypeLayout, FlowCallableLayout {
  final typeEnvironment = typeEnvironment ?? TypeEnvironment(const []);
  final executionShapes = executionShapes ?? ExecutionShapes.defaults;
  final instances = instanceStorage ?? InstanceStorage([]);
  final closures = closureStorage ?? ClosureStorage([]);

  /// Shared descriptor and executable-type ownership across graph revisions.
  final typeImplementations =
      typeImplementations ?? TypeImplementations(runtime: typeRuntime);

  TypeValues get types => typeImplementations.values;
  TypeRelations get relations => typeImplementations.relations;

  /// Capturing facts/layout consumers requires this owner revision to stay fixed.
  int get typeRevision => typeImplementations.revision;

  @override
  ObjectConstant typeConstant(TypeConstant value) =>
      types.constant(value.representedType);
  @override
  TypeConstant? canonicalTypeConstant(ObjectConstant value) =>
      types.canonicalTypeConstant(value);

  @override
  Value? callableConstantField(FunctionConstant value, InstanceField field) {
    final before = closures.classes.toSet();
    final shape = closures.ensureConstant(value);
    for (final declaration in closures.classes) {
      if (!before.contains(declaration)) defineStorage(declaration);
    }
    if (field == FunctionStorage.entries)
      return FunctionEntryTableAddress(shape.target);
    if (field == FunctionStorage.identity)
      return Constant.integer(shape.identity);
    if (field == FunctionStorage.arguments)
      return types.argumentConstants(shape.identityArguments);
    if (field == FunctionStorage.environment ||
        field == FunctionStorage.anchor) {
      return const Constant.nullValue();
    }
    return null;
  }

  final pointers = PointerStorage();
  final nativeCalls = NativeCalls();
  final native = nativeViews ?? NativeViews(nativeLayout);
  final pointerRepresentation = PointerRepresentation(functions);
  final strings = stringStorage ?? StringStorage();
  final records = recordStorage ?? RecordStorage(classes, const []);
  final _classes = {
    for (final declaration in classes) declaration.type: declaration,
  };
  final _storage = <ClassType, ClassStorage>{};

  /// Resolves the persistent cell declaration used by an internal capture.
  CellStorage cellStorageOf(CellType type) {
    final candidates = [
      for (final declaration in _classes.values)
        if (declaration.cellStorage case final storage?
            when storage.slotShape == type.slotShape &&
                storage.isLate == type.isLate &&
                (type.slotShape.hasReferences || storage.content.accepts(type.content)))
          storage,
    ];
    if (candidates.length != 1) {
      throw StateError('Cell capture requires one persistent storage declaration.');
    }
    return candidates.single;
  }


  /// Completes generated storage before any offsets or descriptors are consumed.
  void defineStorage(IrClass declaration) {
    if (_storage.containsKey(declaration.type)) {
      throw StateError('Class storage was already consumed.');
    }
    _classes[declaration.type] = declaration;
  }

  this {
    native.register(classes);
    if (typeImplementations != null &&
        typeRuntime != null &&
        !identical(typeImplementations.values.runtime, typeRuntime)) {
      throw ArgumentError(
        'Type runtime and shared implementation owner disagree.',
      );
    }
    _classes[FfiTypes.pointer] = pointers.declaration;
    _classes[ValueType.string] = strings.declaration;
    for (final declaration in types.classes) {
      _classes.putIfAbsent(declaration.type, () => declaration);
    }
    this.typeImplementations.extend(
      referencedClasses ?? _classes.keys,
      recordStorage: records.declaration?.type,
    );
  }

  TypeTestKind typeTest(ValueType source, ValueType tested) =>
      typeTestKind(source, tested);

  ValueRepresentation representation(ValueType type) =>
      shapeRepresentation(ExecutionShapes.forType(type));

  /// Projects the shared physical contract onto this scalar machine backend.
  ValueRepresentation shapeRepresentation(ExecutionShape shape) {
    if (shape == ExecutionShape.reference) return .reference;
    if (shape == ExecutionShape.word) return .word;
    if (shape == ExecutionShape.floating) return .floating;
    if (shape.components.length == 1 && !shape.hasReferences) return .address;
    throw UnsupportedError('Execution shape requires component allocation.');
  }

  NativeTypeRef shapeCallType(ExecutionShape shape) =>
      shape.storage ?? NativeScalarType(Void);

  NativeTypeRef callType(ValueType type) =>
      shapeCallType(ExecutionShapes.forType(type));

  /// Entry components, including already-proved pointer and lexical transport.
  List<ExecutionShape> entryShapes(FunctionTarget target) => [
    for (final (index, shape)
        in executionShapes.entryOf(target).parameters.indexed)
      pointerRepresentation.contains(target, index)
          ? ExecutionShape.word
          : shape,
    if (typeEnvironment.ownerOf(target)) ExecutionShape.reference,
    for (final _ in typeEnvironment.parametersOf(target))
      ExecutionShape.reference,
    for (final _ in typeEnvironment.lexicalParametersOf(target))
      ExecutionShape.reference,
  ];

  ExecutionShape resultShape(FunctionTarget target) =>
      pointerRepresentation.returnsAddress(target)
      ? ExecutionShape.word
      : executionShapes.entryOf(target).result;

  ExecutionShape slotShape(Object slot) => executionShapes.slotOf(slot);

  /// Legacy scalar semantic views are derived from, never an owner of, storage.
  ValueType carrierType(ExecutionShape shape, ValueType semantic) =>
      switch (shapeRepresentation(shape)) {
        .word => semantic == ValueType.boolean ? .boolean : .integer,
        .floating => .floating,
        .address => .integer,
        .reference =>
          ExecutionShapes.forType(semantic).isReference
              ? semantic
              : ValueType.object.nullable,
      };

  /// A final machine transfer cannot allocate or silently reinterpret storage.
  void checkShapeTransfer(ExecutionShape source, ExecutionShape destination) {
    if (source != destination) {
      throw StateError(
        'Representation changes must be explicit IR: '
        '$source to $destination.',
      );
    }
  }

  /// Selects parameter storage and appends lexical type arguments.
  List<ValueType> entryTypes(FunctionTarget target) => [
    for (final (index, shape) in entryShapes(target).indexed)
      carrierType(
        shape,
        index < target.parameterTypes.length
            ? target.parameterTypes[index]
            : TypeMetadata.type,
      ),
  ];

  /// A legacy semantic view of the declared physical result.
  ValueType returnType(FunctionTarget target) =>
      carrierType(resultShape(target), target.returnType);

  /// Checks transfers before a machine word loses its semantic type.
  void checkTransfer(
    ValueType source,
    ValueType destination, {
    bool constant = false,
  }) {
    source = valueCarrier(source);
    destination = valueCarrier(destination);
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

  bool isBoxable(ValueType type) => _isBoxable(type);

  /// Whether the physical value is traced; stack cells supply their content type.
  bool isReference(ValueType type) => representation(type) == .reference;

  @override
  ObjectLayout objectLayout(ClassType type) => isBoxable(type)
      ? ObjectLayout([representation(type)])
      : storageOf(type).layout;

  ClassStorage storageOf(ClassType type) {
    final declaration = type.declaration;
    if (_storage[declaration] case final known?) return known;
    if (FfiTypes.isCompound(declaration)) native.view(declaration);
    if (declaration == native.buffer) {
      return _storage[declaration] = ClassStorage([], this);
    }
    if (declaration == ValueType.object) {
      return _storage[declaration] = ClassStorage([], this);
    }
    final prefix = native.prefixFields(declaration).toList();
    final definition =
        _classes[declaration] ??
        (prefix.isNotEmpty || FfiTypes.isCompound(declaration)
            ? IrClass(declaration, const [])
            : null);
    if (definition == null) {
      throw UnsupportedError(
        'Native class storage unavailable: ${declaration.library}::${declaration.name}',
      );
    }
    return _storage[declaration] = ClassStorage(
      {
        ...prefix,
        if (declaration.superclass case final parent?)
          ...storageOf(parent).fields,
        for (final field in definition.fields)
          if (field.isLate) ...[
            instances.slots(field).$1,
            instances.slots(field).$2,
          ] else
            field,
      },
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
    );
  }

  @override
  int fieldOffset(InstanceField field) =>
      storageOf(field.owner)
          .offsetOf(field.isLate ? instances.slots(field).$1 : field);
}

/// Declared field identities paired with their shared physical layout.
final class ClassStorage(
  Iterable<InstanceField> fields,
  ProgramLayout program, {
  bool tracesPayload = false,
  final Set<InstanceField> weakFields = const {},
  final Map<InstanceField, InstanceField> ephemerons = const {},
}) {
  final List<InstanceField> fields = .unmodifiable(fields);
  late final ObjectLayout layout;

  this {
    layout = .new(
      this.fields.map((f) => program.shapeRepresentation(program.slotShape(f))),
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

/// Classifies a semantic test before choosing its executable implementation.
TypeTestKind typeTestKind(ValueType source, ValueType tested) {
  source = source.runtimeValueBound;
  tested = tested.runtimeCheckType;
  if (FfiTypes.isPointer(source)) source = FfiTypes.pointerRuntimeType;
  if (tested.accepts(source)) return .constantTrue;
  if (tested == .never ||
      source == .nullType && !tested.mayBeNull ||
      tested == .nullType && !source.mayBeNull ||
      tested.freeTypeParameters.isEmpty &&
          (_isBoxable(source) || FfiTypes.isPointer(source))) {
    return .constantFalse;
  }
  if (tested == .nullType) return .isNull;
  if (tested == .object ||
      !tested.mayBeNull && tested.accepts(source.nonNullable)) {
    return .isNotNull;
  }
  return .subtype;
}

bool _isBoxable(ValueType type) => switch (valueCarrier(type)) {
  ValueType.integer || ValueType.boolean || ValueType.floating => true,
  _ => false,
};
