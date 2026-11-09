import 'package:dartc/object.dart';

/// An object, lazy archive or explicit shared-library dependency.
sealed class const LinkInput() {
  /// Includes every definition and import in [module].
  const factory object(ObjectModule module) = ObjectInput;

  /// Selects members of [archive] only to satisfy unresolved symbols.
  const factory archive(Archive archive) = ArchiveInput;

  /// Declares a loader dependency and its callable symbol bindings.
  ///
  /// [functions] maps unresolved object names to native symbols, including
  /// platform decoration. Included object definitions take precedence.
  /// Mach-O binds to [name]; ELF follows the loader's global symbol search.
  /// The linker does not read the library or verify its exports.
  factory sharedLibrary(String name, {Map<String, String> functions}) =
      SharedLibraryInput;
}

/// An object included independently of references from earlier inputs.
final class const ObjectInput(final ObjectModule module) extends LinkInput;

/// An archive searched according to the target linker's input-order rules.
final class const ArchiveInput(final Archive archive) extends LinkInput;

/// A required library with explicitly named function imports.
final class SharedLibraryInput(
  /// The dependency name or path interpreted by the target loader.
  final String name, {
  Map<String, String> functions = const {},
}) extends LinkInput {
  /// The immutable mapping from object names to loader symbol names.
  final Map<String, String> functions = Map.unmodifiable(functions);

  this {
    for (final value in [name, ...functions.keys, ...functions.values]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw ArgumentError.value(
          value,
          'name',
          'Expected a nonempty C string.',
        );
      }
    }
  }
}
