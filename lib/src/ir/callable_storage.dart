import 'signature.dart';
import 'type.dart';
import 'type_metadata.dart';

/// The common managed prefix of every function value.
abstract final class FunctionStorage() {
  static final type = ClassType(null, 'FunctionStorage');
  static final entries = InstanceField(
    type,
    'entries',
    .integer,
    isFinal: true,
  );
  static final environment = InstanceField(
    type,
    'environment',
    .object.nullable,
    isFinal: true,
  );
  static final identity = InstanceField(
    type,
    'identity',
    .integer,
    isFinal: true,
  );
  static final anchor = InstanceField(
    type,
    'anchor',
    .object.nullable,
    isFinal: true,
  );
  static final arguments = InstanceField(
    type,
    'arguments',
    TypeMetadata.list.nullable,
    isFinal: true,
  );
  static final fields = [entries, environment, identity, anchor, arguments];
}

/// The physical storage of a function value, independent of its calling shape.
///
/// The same object is both a language function and this managed layout. Fields
/// retain captures and descriptors through ordinary traced storage; the entry
/// table contains only addresses demanded by actual calls. A wrapper retains
/// its original function in [origin] and applies [arguments] to that function.
final class CallableStorage({
  required final ClassType type,
  final int? declarationIdentity,
  final FunctionTarget? source,
  final FunctionType? signature,
  final FunctionTarget? initializer,
  Iterable<InstanceField> captures = const [],
  Iterable<TypeParameterType> parameters = const [],
  Iterable<InstanceField> descriptors = const [],
  final InstanceField? origin,
}) {
  final List<InstanceField> captures = .unmodifiable(captures);
  final List<TypeParameterType> parameters = .unmodifiable(parameters);
  final List<InstanceField> descriptors = .unmodifiable(descriptors);

  InstanceField get entries => FunctionStorage.entries;
  InstanceField get environment => FunctionStorage.environment;
  InstanceField get identity => FunctionStorage.identity;
  InstanceField get anchor => FunctionStorage.anchor;
  InstanceField get arguments => FunctionStorage.arguments;

  Iterable<InstanceField> get prefix => [
    entries,
    environment,
    identity,
    anchor,
    arguments,
  ];

  Iterable<InstanceField> get fields => [
    ...prefix,
    ...captures,
    ...descriptors,
    ?origin,
  ];

  this {
    final prefixFields = prefix.toList();
    if (type.isAbstract ||
        type.typeParameters.isNotEmpty ||
        prefixFields.toSet().length != prefixFields.length ||
        fields.any(
          (field) =>
              !field.isFinal ||
              field.isLate ||
              field.initializer != null ||
              type.asInstanceOf(field.owner) == null,
        ) ||
        entries.type != ValueType.integer ||
        identity.type != ValueType.integer ||
        environment.type != ValueType.object.nullable ||
        anchor.type != ValueType.object.nullable ||
        arguments.type != TypeMetadata.list.nullable ||
        this.parameters.length != this.descriptors.length ||
        this.parameters.toSet().length != this.parameters.length ||
        this.descriptors.any((field) => field.type != TypeMetadata.type) ||
        (source == null) != (origin != null) ||
        source != null &&
            (signature == null ||
                declarationIdentity == null ||
                declarationIdentity! < 0) ||
        source == null &&
            (declarationIdentity != null ||
                signature != null ||
                this.captures.isNotEmpty ||
                this.parameters.isNotEmpty) ||
        origin != null && origin!.type != ValueType.function ||
        initializer != null &&
            (initializer!.owner != type ||
                initializer!.kind != FunctionKind.initializer)) {
      throw ArgumentError('Invalid callable storage contract.');
    }
  }
}
