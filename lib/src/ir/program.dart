import 'function.dart';
import 'signature.dart';
import 'type.dart';

/// A class definition and the instance storage introduced by that class.
final class IrClass(
  /// The nominal identity shared with its members and uses.
  final ClassType type,
  Iterable<InstanceField> fields,
) {
  /// Declared fields in initialization order, excluding inherited storage.
  final List<InstanceField> fields = .unmodifiable(fields);

  this {
    final names = <String>{};
    for (final field in this.fields) {
      if (field.owner != type || !names.add(field.name)) {
        throw ArgumentError('Foreign or repeated field in ${type.dartName}.');
      }
    }
  }
}

/// The class definitions and callable bodies in a batch of checked libraries.
///
/// A reference to a declaration outside this batch is an import.
final class IrProgram(
  Iterable<IrClass> classes,
  Iterable<IrFunction> functions,
) {
  /// The class definitions supplied by the input libraries.
  final List<IrClass> classes = .unmodifiable(classes);

  /// The verified bodies supplied by the input libraries.
  final List<IrFunction> functions = .unmodifiable(functions);

  /// Writes declared storage and the control-flow graph of each body to [output].
  void writeTo(StringSink output) {
    String label(ClassType type) => '${type.library}::${type.dartName}';
    for (final declaration in classes) {
      final type = declaration.type;
      final parent = type.superclass;
      final interfaces = type.interfaces;
      output.writeln(
        '${type.isAbstract ? 'abstract ' : ''}class ${label(type)}'
        '${parent == null ? '' : ' extends ${label(parent)}'}'
        '${interfaces.isEmpty ? '' : ' implements ${interfaces.map(label).join(', ')}'}',
      );
      for (final field in declaration.fields) {
        output.writeln(
          '  ${field.isFinal ? 'final ' : ''}${field.type.dartName} ${field.name}',
        );
      }
    }
    for (final function in functions) {
      function.writeTo(output);
    }
  }

  this {
    final owners = {
      for (final c in this.classes) (c.type.library, c.type.dartName): c.type,
    };
    if (owners.length != this.classes.length) {
      throw ArgumentError('Repeated class.');
    }
    final names = <(Uri, ClassType?, FunctionKind, String)>{};
    for (final f in this.functions) {
      final t = f.target, owner = t.owner;
      if (owner != null && owners[(owner.library, owner.dartName)] != owner) {
        throw ArgumentError('Body belongs to an undeclared class.');
      }
      if (!names.add((t.library, owner, t.kind, t.name))) {
        throw ArgumentError('Repeated callable body.');
      }
    }
  }
}
