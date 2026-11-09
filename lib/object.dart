/// Relocatable native sections, symbols, references and indexed static archives.
library;

export 'src/object/object_module.dart' show ObjectModule;
export 'src/object/section.dart' show Section, SectionKind;
export 'src/object/symbol.dart' show Symbol, SymbolBinding, SymbolKind;
export 'src/object/relocation.dart' show Relocation;
export 'src/object/object_format.dart' show ObjectFormat;
export 'src/object/archive.dart' show Archive, ArchiveMember;
export 'src/object/archive_writer.dart' show ArchiveWriter;
