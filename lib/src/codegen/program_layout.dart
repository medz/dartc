import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Assigns physical storage to declaration identities within one compilation.
final class ProgramLayout(IrProgram program) {
  final _classes = {
    for (final declaration in program.classes) declaration.type: declaration,
  };
  final _storage = <ClassType, ClassStorage>{};

  ValueRepresentation representation(ValueType type) {
    if (type == .integer || type == .boolean) return .word;
    if (type == .floating) return .floating;
    if (FfiTypes.isPointer(type)) return .address;
    if (type is CellType || type == .voidType || type == .never) {
      throw UnsupportedError('Native value representation: $type');
    }
    return .reference;
  }

  /// Checks transfers before a machine word loses its semantic type.
  void checkTransfer(ValueType source, ValueType destination) {
    if (representation(source) != representation(destination)) {
      throw UnsupportedError(
        'Native representation conversion: $source to $destination',
      );
    }
  }

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
    return _storage[declaration] = ClassStorage([
      if (declaration.superclass case final parent?)
        ...storageOf(parent).fields,
      ...definition.fields,
    ], this);
  }

  int fieldOffset(InstanceField field) =>
      storageOf(field.owner).offsetOf(field);
}

/// Declared field identities paired with their shared physical layout.
final class ClassStorage(
  Iterable<InstanceField> fields,
  ProgramLayout program,
) {
  final List<InstanceField> fields = .unmodifiable(fields);
  late final ObjectLayout layout;

  this {
    layout = .new(this.fields.map((f) => program.representation(f.type)));
  }

  int offsetOf(InstanceField field) {
    final index = fields.indexOf(field);
    if (index < 0) {
      throw ArgumentError('Undeclared native field: ${field.name}');
    }
    return layout.offsetOf(index);
  }
}
