import 'function.dart';
import 'signature.dart';
import 'type.dart';

/// A class definition and the instance storage introduced by that class.
final class IrClass(
  /// The nominal identity shared with its members and uses.
  final ClassType type,
  Iterable<InstanceField> fields, {
  Iterable<FunctionTarget> members = const [],
  Iterable<FunctionTarget> constructors = const [],
}) {
  /// Declared fields in initialization order, excluding inherited storage.
  final List<InstanceField> fields = .unmodifiable(fields);

  /// Instance members declared here, including implicit accessors and abstract members.
  final Map<MemberSelector, FunctionTarget> members = _members(type, members);

  /// Declared generative and factory constructors, including redirects without a body.
  final Map<String, FunctionTarget> constructors = _constructors(
    type,
    constructors,
  );

  static Map<MemberSelector, FunctionTarget> _members(
    ClassType type,
    Iterable<FunctionTarget> declarations,
  ) {
    final result = <MemberSelector, FunctionTarget>{};
    for (final member in declarations) {
      if (member.owner != type ||
          !member.kind.isVirtual ||
          result.containsKey(member.selector)) {
        throw ArgumentError('Foreign or repeated instance member.');
      }
      result[member.selector] = member;
    }
    return .unmodifiable(result);
  }

  static Map<String, FunctionTarget> _constructors(
    ClassType type,
    Iterable<FunctionTarget> declarations,
  ) {
    final result = <String, FunctionTarget>{};
    for (final ctor in declarations) {
      if (ctor.owner != type ||
          (ctor.kind != .initializer && ctor.kind != .factory) ||
          result.containsKey(ctor.name)) {
        throw ArgumentError('Foreign or repeated constructor.');
      }
      result[ctor.name] = ctor;
    }
    return .unmodifiable(result);
  }

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
  Iterable<IrFunction> functions, {
  Iterable<GlobalVariable> globals = const [],
}) {
  /// The class definitions supplied by the input libraries.
  final List<IrClass> classes = .unmodifiable(classes);

  /// The verified bodies supplied by the input libraries.
  final List<IrFunction> functions = .unmodifiable(functions);

  /// Top-level and static storage, excluding compile-time constants.
  final List<GlobalVariable> globals = .unmodifiable(globals);

  late final _definitions = {for (final c in classes) c.type: c};

  /// Resolves [member] on [receiver], returning `null` if the batch supplies no implementation.
  FunctionTarget? dispatch(ClassType receiver, FunctionTarget member) {
    if (!member.kind.isVirtual ||
        receiver.asInstanceOf(member.owner!) == null) {
      throw ArgumentError('Incompatible dispatch receiver.');
    }
    final selector = member.selector;
    for (ClassType? type = receiver; type != null; type = type.superclass) {
      final definition = _definitions[type.declaration];
      if (definition == null) return null;
      final target = definition.members[selector];
      if (target != null && !target.isAbstract) return target;
    }
    return null;
  }

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
      for (final ctor in declaration.constructors.values) {
        if (ctor.redirect case final destination?) {
          output.writeln(
            '  factory ${ctor.name} = ${label(ctor.redirectOwnerType ?? destination.owner!)}.${destination.name}',
          );
        }
      }
    }
    for (final global in globals) {
      final owner = global.owner;
      output.writeln(
        'global ${global.isLate ? 'late ' : ''}${global.isFinal ? 'final ' : ''}'
        '${global.type.dartName} ${global.library}::'
        '${owner == null ? '' : '${owner.dartName}.'}${global.name}'
        '${global.initializer == null ? '' : ' = ${global.initializer!.name}'}',
      );
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
    final locals = <(FunctionTarget, int)>{};
    final bodies = {for (final f in this.functions) f.target};
    final globalNames = <(Uri, ClassType?, String)>{};
    final slots = this.globals.toSet();
    for (final global in this.globals) {
      if (!globalNames.add((global.library, global.owner, global.name))) {
        throw ArgumentError('Repeated global declaration.');
      }
      final owner = global.owner;
      if (owner != null && owners[(owner.library, owner.dartName)] != owner) {
        throw ArgumentError('Global belongs to an undeclared class.');
      }
      if (global.initializer case final initializer?
          when !bodies.contains(initializer)) {
        throw ArgumentError('Missing global initializer body.');
      }
    }
    for (final f in this.functions) {
      if (!bodies.containsAll(f.closures)) {
        throw ArgumentError('Missing lexical function body.');
      }
      if (!slots.containsAll(f.globals)) {
        throw ArgumentError('Global operation references undeclared storage.');
      }
      final t = f.target, owner = t.owner;
      if (owner != null && owners[(owner.library, owner.dartName)] != owner) {
        throw ArgumentError('Body belongs to an undeclared class.');
      }
      if (t.enclosing case final outer?) {
        if (!bodies.contains(outer) || !locals.add((outer, t.sourceOffset!))) {
          throw ArgumentError('Invalid lexical function declaration.');
        }
      } else if (!names.add((t.library, owner, t.kind, t.name))) {
        throw ArgumentError('Repeated callable body.');
      }
      if (t.kind.isVirtual && _definitions[owner]?.members[t.selector] != t) {
        throw ArgumentError(
          'Instance body does not match the declared member.',
        );
      }
      if ((t.kind == .factory || t.kind == .initializer) &&
          _definitions[owner]!.constructors[t.name] != t) {
        throw ArgumentError('Body does not match a declared constructor.');
      }
    }

    for (final c in this.classes) {
      for (final ctor in c.constructors.values) {
        final destination = ctor.redirect;
        final definition = _definitions[destination?.owner];
        if (destination != null &&
            definition != null &&
            definition.constructors[destination.name] != destination) {
          throw ArgumentError(
            'Factory redirects to an undeclared constructor.',
          );
        }
        if (ctor.redirect == null && !bodies.contains(ctor)) {
          throw ArgumentError('Missing constructor body.');
        }
      }
      for (final member in c.members.values) {
        if (!member.isAbstract && !bodies.contains(member)) {
          throw ArgumentError('Missing member body.');
        }
      }
    }
  }
}
