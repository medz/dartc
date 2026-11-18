import 'core_types.dart';
import 'callable_storage.dart';
import 'cell_storage.dart';
import 'ffi_types.dart';
import 'function.dart';
import 'block.dart';
import 'value.dart';
import 'native_boundary_bindings.dart';
import 'execution_shape.dart';
import 'signature.dart';
import 'type.dart';
import 'verify.dart';

/// A class definition and the instance storage introduced by that class.
final class IrClass(
  /// The nominal identity shared with its members and uses.
  final ClassType type,
  Iterable<InstanceField> fields, {
  Iterable<FunctionTarget> members = const [],
  Iterable<FunctionTarget> implementations = const [],
  Iterable<FunctionTarget> constructors = const [],
  Iterable<MemberSelector> unsupportedForwarders = const [],
  Iterable<InstanceField> weakFields = const [],
  Map<InstanceField, InstanceField> ephemerons = const {},

  /// Whether variable payload words contain references; requires Object as the
  /// direct superclass and no fixed fields.
  final bool referencePayload = false,

  /// The concrete carrier of structural records; all payload words are references.
  final bool recordStorage = false,

  /// Storage for a concrete class with one type parameter implementing `List<E>`.
  /// The fields are length and a traced non-generic buffer; spread
  /// takes `List<T>` and `Iterable<Object?>` and returns void.
  final ({InstanceField length, InstanceField data, FunctionTarget spread})?
  listStorage,

  /// The real native-view prefix and optional ordinary initializer.
  ///
  /// Inheriting views reuse the ancestor's exact field identities. The owner
  /// field is a strong reference; native bytes themselves remain untraced.
  /// This contract survives graph rewrites and does not depend on field names
  /// or an in-memory representation owner.
  final ({
    InstanceField address,
    InstanceField owner,
    FunctionTarget? initializer,
  })?
  nativeViewStorage,

  /// The explicit physical layout of a language function value.
  final CallableStorage? callableStorage,

  /// The typed backing and fixed payload carrier of an internal capture cell.
  final CellStorage? cellStorage,
}) {
  /// Declared fields in initialization order, excluding inherited storage.
  final List<InstanceField> fields = .unmodifiable(fields);

  /// Nullable reference slots that do not retain their contents.
  final Set<InstanceField> weakFields = .unmodifiable(weakFields);

  /// Key/value pairs retained only when both the owner and key are reachable.
  final Map<InstanceField, InstanceField> ephemerons = .unmodifiable(
    ephemerons,
  );

  /// Instance members declared here, including implicit accessors and abstract members.
  final Map<MemberSelector, FunctionTarget> members = _members(type, members);

  /// Concrete entries for abstract declarations whose inherited entry differs.
  final Map<MemberSelector, FunctionTarget> implementations = _members(
    type,
    implementations,
  );

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
        throw ArgumentError(
          'Foreign or repeated instance member: ${type.dartName}.${member.name} (${member.owner?.dartName}).',
        );
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
    if (cellStorage case final storage?) {
      if (storage.type != type || callableStorage != null ||
          storage.fields.any((field) => !this.fields.contains(field) ||
              this.weakFields.contains(field) || this.ephemerons.containsKey(field) ||
              this.ephemerons.containsValue(field)) ||
          this.constructors[storage.initializer.name] != storage.initializer) {
        throw ArgumentError('Cell fields require their declared strong storage.');
      }
    }
    if (callableStorage case final storage?) {
      if (storage.type != type ||
          storage.fields.any(
            (field) => field.owner == type && !this.fields.contains(field),
          ) ||
          storage.fields.any(this.weakFields.contains) ||
          storage.fields.any(this.ephemerons.containsKey) ||
          storage.fields.any(this.ephemerons.containsValue) ||
          storage.initializer != null &&
              this.constructors[storage.initializer!.name] !=
                  storage.initializer) {
        throw ArgumentError(
          'Callable fields require their declared strong storage.',
        );
      }
    }
    if (recordStorage &&
        (!referencePayload ||
            type.isAbstract ||
            type.typeParameters.isNotEmpty ||
            type.asInstanceOf(ValueType.record) == null)) {
      throw ArgumentError('Records require concrete, traced payload storage.');
    }
    if (referencePayload &&
        (this.fields.isNotEmpty || type.superclass != ValueType.object)) {
      throw ArgumentError(
        'Reference payload storage must directly extend Object without fields.',
      );
    }
    if (listStorage case final storage?) {
      final element = type.typeParameters.singleOrNull;
      final parameter = storage.spread.typeParameters.singleOrNull;
      if (type.isAbstract ||
          element == null ||
          CoreTypes.view(type, CoreTypes.list) != CoreTypes.listOf(element) ||
          storage.length == storage.data ||
          ![storage.length, storage.data].every(this.fields.contains) ||
          storage.length.type != ValueType.integer ||
          storage.data.type is! ClassType ||
          storage.data.type.freeTypeParameters.isNotEmpty ||
          storage.spread.kind != FunctionKind.function ||
          parameter == null ||
          storage.spread.returnType != ValueType.voidType ||
          storage.spread.signature.optionalPositional != 0 ||
          storage.spread.signature.namedParameters.isNotEmpty ||
          storage.spread.parameterTypes.length != 2 ||
          storage.spread.parameterTypes[0] != CoreTypes.listOf(parameter) ||
          storage.spread.parameterTypes[1] !=
              CoreTypes.iterableOf(ValueType.object.nullable)) {
        throw ArgumentError('Invalid List storage contract.');
      }
    }
    if (nativeViewStorage case final storage?) {
      final slots = [storage.address, storage.owner];
      final initializer = storage.initializer;
      if (type.typeParameters.isNotEmpty ||
          storage.address == storage.owner ||
          storage.address.owner != storage.owner.owner ||
          storage.address.owner != FfiTypes.nativeViewPrefix(type) ||
          type.asInstanceOf(storage.address.owner) == null ||
          storage.address.type != ValueType.integer ||
          storage.owner.type != ValueType.object.nullable ||
          slots.any(
            (field) =>
                !field.isFinal || field.isLate || field.initializer != null,
          ) ||
          (storage.address.owner == type &&
              !slots.every(this.fields.contains)) ||
          slots.any(this.weakFields.contains) ||
          slots.any(this.ephemerons.containsKey) ||
          slots.any(this.ephemerons.containsValue) ||
          initializer != null &&
              (initializer.owner != type ||
                  initializer.kind != FunctionKind.initializer ||
                  initializer.typeParameters.isNotEmpty ||
                  initializer.signature !=
                      FunctionType(type, [
                        ValueType.integer,
                        ValueType.object.nullable,
                      ]) ||
                  this.constructors[initializer.name] != initializer)) {
        throw ArgumentError('Invalid native view storage contract.');
      }
    }
    if (!identical(type, type.declaration)) {
      throw ArgumentError('A class definition requires its declaration.');
    }
    for (final entry in this.implementations.entries) {
      final declaration = this.members[entry.key], body = entry.value;
      if (declaration == null ||
          !declaration.isAbstract ||
          body.isAbstract ||
          !declaration.signature
              .instantiate(declaration.typeParameters)
              .accepts(
                body.reifiedSignature.instantiate(declaration.typeParameters),
              )) {
        throw ArgumentError('Incompatible abstract member implementation.');
      }
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
    final conditional = {...this.ephemerons.keys, ...this.ephemerons.values};
    if (conditional.length != this.ephemerons.length * 2 ||
        conditional.any(this.weakFields.contains)) {
      throw ArgumentError('Repeated conditional reference slot.');
    }
    for (final field in {...this.weakFields, ...conditional}) {
      if (!this.fields.contains(field) ||
          field.isLate ||
          !field.type.mayBeNull) {
        throw ArgumentError('Weak storage requires a declared nullable field.');
      }
    }
  }
}

/// The class definitions and callable bodies in a batch of checked libraries.
///
/// A reference to a declaration outside this batch is an import.
/// Static bodies can belong to imported classes; instance bodies and
/// constructors require their declaring class definition.
final class IrProgram(
  Iterable<IrClass> classes,
  Iterable<IrFunction> functions, {
  Iterable<GlobalVariable> globals = const [],
  Iterable<IrExternal> externals = const [],

  /// Existing native entries and module ownership, preserved by graph rewrites.
  final NativeBoundaryBindings? nativeBoundaries,

  /// Persistent entry and storage choices shared by every execution consumer.
  final ExecutionShapes? executionShapes,
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
      final target =
          definition?.implementations[selector] ??
          definition?.members[selector];
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
    String label(ClassType type) =>
        '${type.library ?? '<generated>'}::${type.dartName}';
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
      if (declaration.nativeViewStorage case final storage?) {
        output.writeln(
          '  native-view address ${label(storage.address.owner)}.${storage.address.name}'
          ' owner ${label(storage.owner.owner)}.${storage.owner.name}'
          '${storage.initializer == null ? '' : ' initializer ${storage.initializer!.name}'}',
        );
      }
      for (final ctor in declaration.constructors.values) {
        if (ctor.redirect case final destination?) {
          output.writeln(
            '  factory ${ctor.name} = ${label(ctor.redirectOwnerType ?? destination.owner!)}.${destination.name}',
          );
        }
      }
      for (final entry in declaration.implementations.entries) {
        output.writeln(
          '  ${entry.key.name}: ${declaration.members[entry.key]!.signature.dartName}'
          ' -> entry ${entry.value.signature.dartName}',
        );
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
        'external ${t.kind.name} ${t.library ?? '<generated>'}::'
        '${t.owner == null ? '' : '${t.owner!.name}.'}${t.name}: ${t.signature.dartName}',
      );
    }
    for (final function in functions) {
      function.writeTo(output);
    }
  }

  this {
    nativeBoundaries?.checkProgram(this);
    (Object, String) className(ClassType type) =>
        (type.library ?? type.declaration, type.name);
    final owners = <(Object, String), ClassType>{};
    for (final c in this.classes) {
      if (owners.containsKey(className(c.type))) {
        throw ArgumentError(
          'Repeated class: ${c.type.library}::${c.type.name}',
        );
      }
      owners[className(c.type)] = c.type;
    }
    for (final c in this.classes) {
      if (c.nativeViewStorage case final storage?) {
        final prefix = _definitions[storage.address.owner]?.nativeViewStorage;
        if (prefix == null ||
            prefix.address != storage.address ||
            prefix.owner != storage.owner) {
          throw ArgumentError(
            'Native view prefix requires its declared field identities.',
          );
        }
        for (
          ClassType? parent = c.type.superclass;
          parent != null;
          parent = parent.superclass
        ) {
          final inherited = _definitions[parent.declaration]?.nativeViewStorage;
          if (inherited != null &&
              (inherited.address != storage.address ||
                  inherited.owner != storage.owner)) {
            throw ArgumentError(
              'Inheriting native views must share their prefix.',
            );
          }
        }
      }
    }
    (Object, ClassType?, FunctionKind, String, Object?) nameOf(
      FunctionTarget t,
    ) => (
      t.library ?? t,
      t.owner,
      t.kind,
      t.kind.isVirtual ? t.selector.name : t.name,
      t.kind.isVirtual ? t.selector.privateScope : null,
    );
    final names =
        <(Object, ClassType?, FunctionKind, String, Object?), FunctionTarget>{};
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
      if (owner != null && owners[className(owner)] != owner) {
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
      if (owner != null &&
          (t.kind.hasReceiver || t.kind == .factory) &&
          owners[className(owner)] != owner) {
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
      if (t.kind.isVirtual &&
          (_definitions[owner]?.implementations[t.selector] ??
                  _definitions[owner]?.members[t.selector]) !=
              t) {
        throw ArgumentError(
          'Instance body does not match the declared member: ${t.owner?.dartName}.${t.name}.',
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
      final identity = owners.putIfAbsent(
        className(type),
        () => type.declaration,
      );
      if (!identical(identity, type.declaration)) {
        throw ArgumentError('Conflicting class identity for ${type.name}.');
      }
      final definition = _definitions[identity];
      if (type.library == null && definition == null) {
        throw ArgumentError(
          'Missing generated class definition: ${type.name}.',
        );
      }
      return definition;
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
      if (target.library == null &&
          implementationOf(target) == null &&
          !target.isAbstract &&
          target.redirect == null) {
        throw ArgumentError(
          'Missing generated callable definition: ${target.name}.',
        );
      }
      final owner = target.owner;
      final c = owner == null ? null : definitionOf(owner);
      final known = switch (target.kind) {
        .closure => implementationOf(target)?.target,
        .getter || .setter || .method when c != null =>
          target.isAbstract
              ? c.members[target.selector]
              : c.implementations[target.selector] ??
                    c.members[target.selector],
        .initializer || .factory when c != null => c.constructors[target.name],
        .fieldInitializer when c != null => fieldInitializers.lookup(target),
        _ => names.putIfAbsent(nameOf(target), () => target),
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

    final deferred = <(Uri, String), Uri>{};
    for (final f in _implementations.values) {
      for (final reference in f.deferredImports) {
        if (deferred.putIfAbsent((
              reference.unit,
              reference.prefix,
            ), () => reference.library) !=
            reference.library) {
          throw ArgumentError('Conflicting deferred import prefix.');
        }
      }
      if (f.target.owner case final owner?) definitionOf(owner);
      f.referencedClasses.forEach(definitionOf);
      f.callees
          .followedBy(f.virtualMembers.map((m) => m.target))
          .forEach(checkTarget);
      if (f is IrFunction) {
        for (final block in f.blocks) {
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            final field = switch (operation) {
              LoadField(:final field) ||
              StoreField(:final field) ||
              InitializeStorageField(:final field) => field,
              _ => null,
            };
            final view = operation.storageContract;
            final fieldStorage = field == null
                ? null
                : definitionOf(field.owner)?.cellStorage;
            if (fieldStorage case final storage?) {
              if (view == null ||
                  view.storageType.declaration != storage.type ||
                  !view.fields.containsKey(field)) {
                throw ArgumentError('Cell slot access requires its invariant view.');
              }
            }
            if (view != null) {
              final storage = definitionOf(view.storageType.declaration)?.cellStorage;
              final capability = view.capability;
              if (capability is! CellType || storage == null ||
                  storage.viewOf(capability) != view) {
                throw ArgumentError('Storage view disagrees with its allocation declaration.');
              }
            }
            if (operation case FunctionCall(entryBinding: final binding?) ||
                DynamicDispatch(entryBinding: final binding?)) {
              binding.checkExecution(executionShapes ?? ExecutionShapes.defaults);
            }
            if (operation case InstanceCall(entryBinding: final binding?) || BindMethod(entryBinding: final binding?)) {
              binding.checkExecution(executionShapes ?? ExecutionShapes.defaults);
            }
          }
        }
      }
      for (final storage in f.cellStorages) {
        if (!identical(definitionOf(storage.type)?.cellStorage, storage)) {
          throw ArgumentError('A cell view requires its declared storage contract.');
        }
      }
      for (final field in f.fields) {
        final c = definitionOf(field.owner);
        if (c != null && !c.fields.contains(field)) {
          throw ArgumentError(
            'Undeclared field ${field.owner.name}.${field.name}.',
          );
        }
      }
      for (final object in f.objects) {
        if (object.payload.isNotEmpty &&
            definitionOf(object.type as ClassType)?.referencePayload != true) {
          throw ArgumentError(
            'Constant reference payload requires a declared storage contract.',
          );
        }
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
    for (final f in _implementations.values) {
      for (final object in f.moduleObjects) {
        final declaration = definitionOf(object.type);
        if (declaration == null || declaration.referencePayload) {
          throw ArgumentError(
            'Module object requires declared fixed-size storage.',
          );
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
          throw ArgumentError(
            'Missing constructor implementation: ${c.type.name}.${ctor.name}.',
          );
        }
      }
      for (final member in [...c.members.values, ...c.implementations.values]) {
        checkSignature(member);
        if (!member.isAbstract && implementationOf(member) == null) {
          throw ArgumentError(
            'Missing member implementation: ${c.type.name}.${member.name}.',
          );
        }
      }
    }
    sealTypes([
      ...owners.values,
      for (final global in this.globals) global.type,
    ]);
  }
}
