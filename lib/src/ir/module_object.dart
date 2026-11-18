import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// One mutable object whose identity and storage last until module unload.
///
/// Initial bindings are installed once when the module loads. Omitted fields
/// remain unbound; zero-filled physical storage does not bind a Dart value.
/// Equal types and bindings do not merge object identities. Every retained
/// declaration participates in the module's strong, weak and conditional roots.
/// Variable inline payload is not supported by this storage contract.
final class ModuleObject(
  final ClassType type, {
  Map<InstanceField, Constant> initialFields = const {},
}) {
  final Map<InstanceField, Constant> initialFields = .unmodifiable(
    initialFields,
  );

  this {
    type.validateTypeArguments();
    if (type.isAbstract || type.freeTypeParameters.isNotEmpty) {
      throw ArgumentError(
        'Module storage requires a concrete, closed object type.',
      );
    }
    for (final MapEntry(key: field, value: initial)
        in this.initialFields.entries) {
      if (!field.typeFor(type).accepts(initial.type)) {
        throw ArgumentError('Incompatible module field initialization.');
      }
    }
  }
}
