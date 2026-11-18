import 'package:dartc/abi.dart' show NativeLayout;
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Owns native view fields and executable storage bodies for one compilation.
///
/// Materialized [IrClass.nativeViewStorage] contracts retain field and initializer
/// identities when a checked graph enters a fresh compilation. A supported view
/// hierarchy shares one real prefix, followed by its ordinary managed fields.
/// Native bytes themselves are untraced payload storage.
final class NativeViews(final NativeLayout layout) {
  final buffer = ClassType(null, '_NativeBytes');
  final _views = <ClassType, NativeViewStorage>{};
  final _prefixes = <ClassType, _NativePrefix>{};
  final _sources = <ClassType, IrClass>{};
  final _copies = <(ClassType, bool), IrFunction>{};
  var _revision = 0;

  /// The revision of the stable field and executable declaration set.
  int get revision => _revision;

  /// The address slot shared by every supported native view representation.
  static final addressOffset = ObjectLayout([.word, .reference]).offsetOf(0);

  /// Registers current source metadata without replacing any source member.
  void register(Iterable<IrClass> classes) {
    final declarations = classes.toList();
    for (final declaration in declarations) {
      _sources[declaration.type] = declaration;
      if (declaration.nativeViewStorage case final storage?) {
        final type = storage.address.owner;
        final known = _prefixes[type];
        if (known != null &&
            (known.address != storage.address ||
                known.owner != storage.owner)) {
          throw StateError('Conflicting native view prefix identities.');
        }
        if (known == null) {
          _prefixes[type] = _NativePrefix(type, storage.address, storage.owner);
          _revision++;
        }
      }
    }
    // Adopt every materialized contract before demanding any fresh prefix; the
    // caller's class order need not put an ancestor before its concrete views.
    for (final declaration in declarations) {
      if (FfiTypes.isCompound(declaration.type)) {
        final prefix = FfiTypes.nativeViewPrefix(declaration.type);
        if (prefix != null) _prefix(prefix);
      }
    }
  }

  _NativePrefix _prefix(ClassType type) => _prefixes.putIfAbsent(type, () {
    _revision++;
    final reserved =
        _sources[type]?.fields.map((field) => field.name).toSet() ?? <String>{};
    String name(String candidate) {
      while (!reserved.add(candidate)) {
        candidate = '${candidate}_';
      }
      return candidate;
    }

    return _NativePrefix(
      type,
      InstanceField(type, name('_nativeAddress'), .integer, isFinal: true),
      InstanceField(
        type,
        name('_nativeOwner'),
        .object.nullable,
        isFinal: true,
      ),
    );
  });

  /// Returns the stable view identity, rejecting unsupported storage inheritance.
  ///
  /// SDK views share the canonical Compound prefix. Independent IR may use a
  /// standalone native compound or a chain of native compound declarations.
  /// Ordinary non-FFI parents are not silently given native view slots.
  NativeViewStorage view(ClassType type) {
    type = type.declaration;
    return _views.putIfAbsent(type, () {
      if (!FfiTypes.isCompound(type)) {
        throw ArgumentError('A native compound view is required.');
      }
      final prefix = FfiTypes.nativeViewPrefix(type);
      if (prefix == null) {
        throw UnsupportedError(
          'Native view storage requires a closed native compound inheritance chain: ${type.dartName}',
        );
      }
      final fields = _prefix(prefix);
      _revision++;
      return NativeViewStorage._(type, fields, () => _sources[type]);
    });
  }

  /// Prefix fields declared by this class, absent on all inheriting views.
  Iterable<InstanceField> prefixFields(ClassType type) =>
      _prefixes[type.declaration]?.fields ?? const [];

  /// Adds demanded storage declarations and actual bodies to the same program.
  ///
  /// Source members, constructors, weak/conditional slots and defaults survive.
  /// A second normalization returns the same program once nothing was demanded.
  IrProgram normalize(
    IrProgram program, {
    Iterable<IrFunction>? rewrittenFunctions,
  }) {
    register(program.classes);
    final declarations = {for (final c in program.classes) c.type: c};
    var changed = rewrittenFunctions != null;
    void merge(
      ClassType type,
      Iterable<InstanceField> fields, {
      _NativePrefix? prefix,
      FunctionTarget? initializer,
    }) {
      final source = declarations[type];
      final slots = fields.toList();
      final existing = source?.fields ?? const <InstanceField>[];
      final constructors =
          source?.constructors ?? const <String, FunctionTarget>{};
      if (slots.any(
        (field) =>
            existing.any((other) => field != other && field.name == other.name),
      )) {
        throw StateError(
          'Native view fields belong to a different storage owner.',
        );
      }
      final other = initializer == null ? null : constructors[initializer.name];
      if (other != null && other != initializer) {
        throw StateError(
          'Native view initializer conflicts with a source constructor.',
        );
      }
      final storage = prefix == null
          ? source?.nativeViewStorage
          : (
              address: prefix.address,
              owner: prefix.owner,
              initializer:
                  initializer ?? source?.nativeViewStorage?.initializer,
            );
      final complete =
          source != null &&
          slots.every(existing.contains) &&
          source.nativeViewStorage == storage &&
          (initializer == null ||
              constructors[initializer.name] == initializer);
      if (complete) return;
      declarations[type] = IrClass(
        type,
        {...slots, ...existing},
        members: source?.members.values ?? const [],
        implementations: source?.implementations.values ?? const [],
        constructors: {...constructors.values, ?initializer},
        unsupportedForwarders: source?.unsupportedForwarders ?? const {},
        weakFields: source?.weakFields ?? const {},
        ephemerons: source?.ephemerons ?? const {},
        referencePayload: source?.referencePayload ?? false,
        recordStorage: source?.recordStorage ?? false,
        listStorage: source?.listStorage,
        nativeViewStorage: storage,
        callableStorage: source?.callableStorage,
          cellStorage: source?.cellStorage,
      );
      changed = true;
    }

    if (_copies.isNotEmpty) merge(buffer, const []);
    for (final prefix in _prefixes.values) {
      merge(prefix.type, prefix.fields, prefix: prefix);
    }
    for (final view in _views.values) {
      if (view.type.nativeType is NativeCompoundType) {
        merge(
          view.type,
          prefixFields(view.type),
          prefix: view._prefix,
          initializer: view.initializer,
        );
      }
    }
    final functions = {
      for (final function in rewrittenFunctions ?? program.functions)
        function.target: function,
    };
    for (final function in this.functions) {
      if (!functions.containsKey(function.target)) {
        functions[function.target] = function;
        changed = true;
      }
    }
    return changed
        ? IrProgram(
            declarations.values,
            functions.values,
            globals: program.globals,
            nativeBoundaries: program.nativeBoundaries,
            executionShapes: program.executionShapes,
            externals: program.externals,
          )
        : program;
  }

  /// New ordinary bodies that must enter the source graph before selection.
  /// Materialized initializers keep the actual bodies supplied by that graph.
  Iterable<IrFunction> get functions => [
    for (final view in _views.values)
      if (view.type.nativeType is NativeCompoundType &&
          view._source()?.nativeViewStorage?.initializer == null)
        view.function,
    ..._copies.values,
  ];

  /// Returns the stable owned or copying constructor, using ordinary allocation.
  FunctionTarget owned(
    ClassType type, {
    required bool copy,
  }) => _copies.putIfAbsent((type, copy), () {
    _revision++;
    final view = this.view(type);
    final target = FunctionTarget(
      null,
      'native${copy ? 'Copy' : 'Create'}',
      type,
      [.integer, .object.nullable],
    );
    final entry = Block(target.parameterTypes);
    final backing = entry.emit(
      NewPayload(buffer, Constant.integer(layout.of(type.nativeType!).size)),
    );
    final address = entry.emit(
      IntBinary(
        .add,
        entry.emit(ReferenceAddress(backing)),
        const Constant.integer(ObjectHeader.fieldsOffset),
      ),
    );
    if (copy) {
      entry.emit(CopyNative(address, entry.parameters.first, type.nativeType!));
    }
    final result = entry.emit(Construct(view.initializer, [address, backing]));
    entry.emit(KeepAlive(backing));
    entry.emit(KeepAlive(entry.parameters.last));
    entry.finish(Return(result));
    return IrFunction(target, [entry]);
  }).target;
}

final class _NativePrefix(
  final ClassType type,
  final InstanceField address,
  final InstanceField owner,
) {
  late final fields = [address, owner];
}

/// The declared view and the shared real prefix of its native inheritance chain.
final class NativeViewStorage._(
  final ClassType type,
  final _NativePrefix _prefix,
  final IrClass? Function() _source,
) {
  InstanceField get address => _prefix.address;
  InstanceField get owner => _prefix.owner;
  List<InstanceField> get fields => _prefix.fields;

  late final initializer = () {
    if (_source()?.nativeViewStorage?.initializer case final existing?) {
      return existing;
    }
    var name = '_nativeView';
    final reserved = _source()?.constructors.keys.toSet() ?? const <String>{};
    while (reserved.contains(name)) {
      name = '${name}_';
    }
    return FunctionTarget(
      null,
      name,
      .voidType,
      [.integer, .object.nullable],
      owner: type,
      kind: .initializer,
    );
  }();
  late final function = _initialize();

  IrFunction _initialize() {
    final entry = Block(initializer.parameterTypes);
    entry.emit(StoreField(address, entry.parameters[0], entry.parameters[1]));
    entry.emit(StoreField(owner, entry.parameters[0], entry.parameters[2]));
    entry.finish(const Return());
    return IrFunction(initializer, [entry]);
  }
}
