import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';

/// Checked Dart entries and the one generated nominal metadata projection.
final class TypeRuntime(
  final IrProgram program,
  Map<RuntimeRole, FunctionTarget> entries,
  final FunctionTarget supertypes,
) {
  final Map<RuntimeRole, FunctionTarget> _entries = {
    for (final role in _signatures.keys)
      role:
          entries[role] ?? (throw ArgumentError('Missing type runtime: $role')),
  };

  static final _signatures = <RuntimeRole, FunctionType>{
    .typeSubtype: FunctionType(.boolean, [
      TypeMetadata.type,
      TypeMetadata.type,
    ]),
    .typeEquals: FunctionType(.boolean, [TypeMetadata.type, .object.nullable]),
    .typeHash: FunctionType(.integer, [TypeMetadata.type]),
    .typeArgumentsEqual: FunctionType(.boolean, [
      TypeMetadata.list.nullable,
      TypeMetadata.list.nullable,
    ]),
    .typeArgumentsHash: FunctionType(.integer, [TypeMetadata.list.nullable]),
    for (final role in [RuntimeRole.typeNullable, RuntimeRole.typeFutureOr])
      role: FunctionType(TypeMetadata.type, [TypeMetadata.type]),
    .typeParameter: FunctionType(TypeMetadata.type, [
      TypeMetadata.type,
      TypeMetadata.type,
    ]),
    .typeShift: FunctionType(TypeMetadata.type, [
      TypeMetadata.type,
      .integer,
      .integer,
    ]),
    .typeAt: FunctionType(TypeMetadata.type, [
      TypeMetadata.list.nullable,
      .integer,
    ]),
  };

  this {
    for (final MapEntry(key: role, value: signature) in _signatures.entries) {
      final target = _entries[role]!;
      if (target.typeParameters.isNotEmpty ||
          target.signature.optionalPositional != 0 ||
          target.signature.named.isNotEmpty ||
          FunctionType(target.returnType, target.parameterTypes) != signature ||
          program.implementationOf(target) is! IrFunction) {
        throw ArgumentError('Invalid type runtime entry: $role');
      }
    }
    if (supertypes.typeParameters.isNotEmpty ||
        supertypes.signature.optionalPositional != 0 ||
        supertypes.signature.named.isNotEmpty ||
        FunctionType(supertypes.returnType, supertypes.parameterTypes) !=
            FunctionType(TypeMetadata.list.nullable, [TypeMetadata.type]) ||
        program.implementationOf(supertypes) is! IrExternal) {
      throw ArgumentError('Invalid type metadata projection.');
    }
  }

  Iterable<FunctionTarget> get entries => _entries.values;

  FunctionTarget entry(RuntimeRole role) => _entries[role]!;

  FunctionTarget initializer(ClassType type) => program.classes
      .singleWhere((declaration) => declaration.type == type)
      .constructors['new']!;
}
