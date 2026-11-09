import 'package:dartc/object.dart';

/// An ordered input with either an unconditional object or a lazy archive.
sealed class const LinkInput() {
  /// Includes every definition and import in [module].
  const factory object(ObjectModule module) = ObjectInput;

  /// Selects members of [archive] only to satisfy unresolved symbols.
  const factory archive(Archive archive) = ArchiveInput;
}

/// An object included independently of references from earlier inputs.
final class const ObjectInput(final ObjectModule module) extends LinkInput;

/// An archive searched according to the target linker's input-order rules.
final class const ArchiveInput(final Archive archive) extends LinkInput;
