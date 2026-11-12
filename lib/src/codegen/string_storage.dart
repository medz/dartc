import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Owns the built-in UTF-16 layout; checked SDK methods own String algorithms.
final class StringStorage({final IrClass? source}) {
  static const dataOffset = ObjectHeader.fieldsOffset + ObjectHeader.alignment;
  final length = InstanceField(ValueType.string, 'length', .integer);
  late final declaration = IrClass(
    ValueType.string,
    [length],
    members: source?.members.values ?? const [],
    implementations: source?.implementations.values ?? const [],
    constructors: source?.constructors.values ?? const [],
    unsupportedForwarders: source?.unsupportedForwarders ?? const {},
  );

  FunctionTarget _member(FunctionKind kind, String name) =>
      declaration.members[(kind: kind, name: name, privateScope: null)] ??
      (throw ArgumentError(
        'String operations require checked SDK definitions: $name',
      ));

  FunctionTarget? callFor(Instruction operation) => switch (operation) {
    StringCodeUnitAt() => _member(.method, 'codeUnitAt'),
    StringFromCharCode() => declaration.constructors['fromCharCode'],
    StringFromCharCodes() => declaration.constructors['fromCharCodes'],
    StringConcat() => _member(.method, '+'),
    _ => null,
  };

  FunctionTarget get equality => _member(.method, '==');
  FunctionTarget get hash => _member(.getter, 'hashCode');
}
