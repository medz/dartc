import 'function.dart';
import 'signature.dart';
import 'type.dart';
import 'verify.dart';

/// A class definition and the instance storage introduced by that class.
final class IrClass(
  /// The nominal identity shared with its members and uses.
  final ClassType type,
  Iterable<InstanceField> fields, {
  Iterable<FunctionTarget> members = const [],
  Iterable<FunctionTarget> constructors = const [],
  Iterable<MemberSelector> unsupportedForwarders = const [],
}) {
  /// Declared fields in initialization order, excluding inherited storage.
  final List<InstanceField> fields = .unmodifiable(fields);

  /// Instance members declared here, including implicit accessors and abstract members.
  final Map<MemberSelector, FunctionTarget> members = _members(type, members);

  /// Effective typed noSuchMethod forwarders whose execution is not yet modeled.
  ///
  /// These are guards, not implementations. A concrete superclass member still
  /// wins ordinary lookup even if its selector occurs in this set.
  final Set<MemberSelector> unsupportedForwarders = .unmodifiable(
    unsupportedForwarders,
  );

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
    if (!identical(type, type.declaration)) {
      throw ArgumentError('A class definition requires its declaration.');
    }
    for (final selector in this.unsupportedForwarders) {
      checkMemberSelector(selector);
    }
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
  Iterable<IrExternal> externals = const [],
}) {
  /// The class definitions supplied by the input libraries.
  final List<IrClass> classes = .unmodifiable(classes);

  /// The verified bodies supplied by the input libraries.
  final List<IrFunction> functions = .unmodifiable(functions);

  /// External implementations declared in these libraries, with their Dart defaults.
  final List<IrExternal> externals = .unmodifiable(externals);

  /// Top-level and static storage, excluding compile-time constants.
  final List<GlobalVariable> globals = .unmodifiable(globals);

  late final _definitions = {for (final c in classes) c.type: c};
  late final _implementations = <FunctionTarget, IrCallable>{
    for (final f in functions) f.target: f,
    for (final f in externals) f.target: f,
  };

  /// The supplied body or external declaration for [target].
  ///
  /// Returns null for imports, abstract members and redirecting declarations.
  IrCallable? implementationOf(FunctionTarget target) =>
      _implementations[target];

  /// Resolves [member] on [receiver], returning `null` if the batch supplies no implementation.
  FunctionTarget? dispatch(ClassType receiver, FunctionTarget member) {
    if (!member.kind.isVirtual ||
        receiver.asInstanceOf(member.owner!) == null) {
      throw ArgumentError('Incompatible dispatch receiver.');
    }
    return lookupMember(receiver, member.selector).target;
  }

  /// Looks up a selector without a statically resolved declaration.
  ///
  /// A null target with a null boundary proves absence after reaching Object.
  /// Other missing definitions (or an incomplete non-Object hierarchy) report
  /// `unmodeledBoundary` instead. Abstract declarations and interfaces do not
  /// supply implementations; the first concrete member wins regardless of its
  /// call shape or any accumulated unsupported-forwarder guard.
  ({
    FunctionTarget? target,
    ClassType? unmodeledBoundary,
    bool unsupportedForwarder,
  })
  lookupMember(ClassType receiver, MemberSelector selector) {
    checkMemberSelector(selector);
    var unsupportedForwarder = false;
    var type = receiver;
    while (true) {
      final definition = _definitions[type.declaration];
      unsupportedForwarder |=
          definition?.unsupportedForwarders.contains(selector) ?? false;
      final target = definition?.members[selector];
      if (target != null && !target.isAbstract) {
        return (
          target: target,
          unmodeledBoundary: null,
          unsupportedForwarder: unsupportedForwarder,
        );
      }
      if (type.declaration == ValueType.object) {
        return (
          target: null,
          unmodeledBoundary: null,
          unsupportedForwarder: unsupportedForwarder,
        );
      }
      final parent = type.superclass;
      if (definition == null || parent == null) {
        return (
          target: null,
          unmodeledBoundary: type,
          unsupportedForwarder: unsupportedForwarder,
        );
      }
      type = parent;
    }
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
          '  ${field.isLate ? 'late ' : ''}${field.isFinal ? 'final ' : ''}'
          '${field.type.dartName} ${field.name}'
          '${field.initializer == null ? '' : ' = ${field.initializer!.name}'}',
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
    for (final external in externals) {
      final t = external.target;
      output.writeln(
        'external ${t.kind.name} ${t.library}::'
        '${t.owner == null ? '' : '${t.owner!.name}.'}${t.name}: ${t.signature.dartName}',
      );
    }
    for (final function in functions) {
      function.writeTo(output);
    }
  }

  this {
    final owners = {
      for (final c in this.classes) (c.type.library, c.type.name): c.type,
    };
    if (owners.length != this.classes.length) {
      throw ArgumentError('Repeated class.');
    }
    (Uri, ClassType?, FunctionKind, String, Uri?) nameOf(FunctionTarget t) => (
      t.library,
      t.owner,
      t.kind,
      t.kind.isVirtual ? t.selector.name : t.name,
      t.kind.isVirtual ? t.selector.privateLibrary : null,
    );
    final names =
        <(Uri, ClassType?, FunctionKind, String, Uri?), FunctionTarget>{};
    if (_implementations.length !=
        this.functions.length + this.externals.length) {
      throw ArgumentError('Repeated callable implementation.');
    }
    final fieldInitializers = <FunctionTarget>{};
    for (final c in this.classes) {
      for (final field in c.fields) {
        if (field.initializer case final initializer?) {
          if (!fieldInitializers.add(initializer) ||
              implementationOf(initializer) == null) {
            throw ArgumentError('Repeated or missing field initializer body.');
          }
        }
      }
    }
    final globalNames = <(Uri, ClassType?, String)>{};
    final slots = this.globals.toSet();
    for (final global in this.globals) {
      if (!globalNames.add((global.library, global.owner, global.name))) {
        throw ArgumentError('Repeated global declaration.');
      }
      final owner = global.owner;
      if (owner != null && owners[(owner.library, owner.name)] != owner) {
        throw ArgumentError('Global belongs to an undeclared class.');
      }
      if (global.initializer case final initializer?
          when implementationOf(initializer) == null) {
        throw ArgumentError('Missing global initializer body.');
      }
    }
    for (final f in _implementations.values) {
      if (f is IrFunction) {
        if (f.closures.any((t) => implementationOf(t) is! IrFunction)) {
          throw ArgumentError('Missing lexical function body.');
        }
        if (!slots.containsAll(f.globals)) {
          throw ArgumentError(
            'Global operation references undeclared storage.',
          );
        }
      }
      final t = f.target, owner = t.owner;
      if (owner != null && owners[(owner.library, owner.name)] != owner) {
        throw ArgumentError('Body belongs to an undeclared class.');
      }
      if (t.enclosing case final outer?) {
        if (implementationOf(outer) is! IrFunction) {
          throw ArgumentError('Missing enclosing function body.');
        }
      } else if (names.containsKey(nameOf(t))) {
        throw ArgumentError('Repeated callable body.');
      } else {
        names[nameOf(t)] = t;
      }
      if (t.kind.isVirtual && _definitions[owner]?.members[t.selector] != t) {
        throw ArgumentError(
          'Instance body does not match the declared member.',
        );
      }
      if (t.kind == .fieldInitializer && !fieldInitializers.contains(t)) {
        throw ArgumentError(
          'Body does not match a declared field initializer.',
        );
      }
      if ((t.kind == .factory || t.kind == .initializer) &&
          _definitions[owner]!.constructors[t.name] != t) {
        throw ArgumentError('Body does not match a declared constructor.');
      }
    }

    IrClass? definitionOf(ClassType type) {
      final identity = owners.putIfAbsent((
        type.library,
        type.name,
      ), () => type.declaration);
      if (!identical(identity, type.declaration)) {
        throw ArgumentError('Conflicting class identity for ${type.name}.');
      }
      return _definitions[identity];
    }

    void checkType(ValueType type, Set<TypeParameterType> scope) {
      for (final declaration in typeDeclarationsIn(type)) {
        if (declaration is ClassType) {
          definitionOf(declaration);
        } else if (!scope.contains(declaration)) {
          throw ArgumentError('Type parameter outside its declaration.');
        }
      }
    }

    final checkedSignatures = _implementations.keys.toSet();
    void checkSignature(FunctionTarget t) {
      if (checkedSignatures.add(t)) {
        verifyCallable(t, const []).classes.forEach(definitionOf);
      }
    }

    void checkTarget(FunctionTarget target) {
      checkSignature(target);
      final owner = target.owner;
      final c = owner == null ? null : definitionOf(owner);
      final known = switch (target.kind) {
        .getter ||
        .setter ||
        .method when c != null => c.members[target.selector],
        .initializer || .factory when c != null => c.constructors[target.name],
        .fieldInitializer when c != null => fieldInitializers.lookup(target),
        _ => names[nameOf(target)] ?? target,
      };
      // A synthesized concrete forwarder can implement this abstract selector.
      if (!identical(known, target) &&
          !(target.isAbstract &&
              known != null &&
              !known.isAbstract &&
              target.signature == known.signature)) {
        throw ArgumentError(
          'Unbound callable reference to ${target.library}::${owner?.name ?? ''}.${target.name}.',
        );
      }
    }

    for (final f in _implementations.values) {
      f.referencedClasses.forEach(definitionOf);
      f.callees.forEach(checkTarget);
      for (final field in f.fields) {
        final c = definitionOf(field.owner);
        if (c != null && !c.fields.contains(field)) {
          throw ArgumentError(
            'Undeclared field ${field.owner.name}.${field.name}.',
          );
        }
      }
      for (final object in f.objects) {
        for (
          ClassType? t = object.type as ClassType;
          t != null;
          t = t.superclass
        ) {
          final c = definitionOf(t);
          if (c != null && !c.fields.every(object.fields.containsKey)) {
            throw ArgumentError('Incomplete constant storage for ${t.name}.');
          }
        }
      }
    }
    for (final global in this.globals) {
      checkType(global.type, const {});
    }
    for (final c in this.classes) {
      final parameters = c.type.typeParameters.toSet();
      if (parameters.length != c.type.typeParameters.length) {
        throw ArgumentError('Repeated class type parameter in ${c.type.name}.');
      }
      for (final parameter in parameters) {
        checkType(parameter.bound, parameters);
        if (parameter.defaultType case final t?) checkType(t, parameters);
      }
      final views = <ClassType, ClassType>{};
      void visit(ClassType t) {
        final previous = views[t.declaration];
        if (previous != null) {
          if (previous != t) {
            throw ArgumentError(
              'Inconsistent inherited arguments for ${t.name}.',
            );
          }
          return;
        }
        views[t.declaration] = t;
        checkType(t, parameters);
        if (t.superclass case final parent?) visit(parent);
        t.interfaces.forEach(visit);
      }

      visit(c.type);
      for (final field in c.fields) {
        checkType(field.type, parameters);
      }
      for (final ctor in c.constructors.values) {
        checkSignature(ctor);
        if (ctor.redirectOwnerType case final t?) checkType(t, parameters);
        final destination = ctor.redirect;
        if (destination != null) checkTarget(destination);
        if (ctor.redirect == null && implementationOf(ctor) == null) {
          throw ArgumentError('Missing constructor implementation.');
        }
      }
      for (final member in c.members.values) {
        checkSignature(member);
        if (!member.isAbstract && implementationOf(member) == null) {
          throw ArgumentError('Missing member implementation.');
        }
      }
    }
  }
}
