import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';

/// Checked ordinary Dart entries for type operations.
final class TypeRuntime(
  final IrProgram program,
  Map<RuntimeRole, FunctionTarget> entries,
) {
  /// Maps metadata and a declaration shape through the value's own projector.
  FunctionTarget get projection => entry(.typeProjection);
  final Map<RuntimeRole, FunctionTarget> _entries = {
    for (final role in _signatures.keys)
      role:
          entries[role] ?? (throw ArgumentError('Missing type runtime: $role')),
  };

  static final _signatures = <RuntimeRole, FunctionType>{
    .typeProjection: FunctionType(TypeMetadata.type.nullable, [
      TypeMetadata.type,
      .integer,
    ]),
    .typeArgument: TypeMetadata.projectorSignature,
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
    .typeInstantiate: FunctionType(TypeMetadata.type, [
      TypeMetadata.type, TypeMetadata.list.nullable,
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
  }

  /// Binds these entry identities to the current verified graph.
  ///
  /// Constructor and entry lookups must never read a superseded source graph.
  TypeRuntime rebind(IrProgram current) =>
      identical(current, program) ? this : TypeRuntime(current, _entries);

  Iterable<FunctionTarget> get entries => _entries.values;

  FunctionTarget entry(RuntimeRole role) => _entries[role]!;

  FunctionTarget initializer(ClassType type) => program.classes
      .singleWhere((declaration) => declaration.type == type)
      .constructors['new']!;
}
