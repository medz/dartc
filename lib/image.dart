/// Executable files, libraries and object files from emitted machine code.
library;

export 'src/image/archive.dart' show writeArchive;
export 'src/image/elf.dart' show linkElf, linkElfLibrary;
export 'src/image/elf_archive.dart' show writeElfArchive;
export 'src/image/elf_object.dart' show writeElfObject;
export 'src/image/macho.dart' show linkMacho, linkMachoLibrary;
export 'src/image/macho_object.dart' show writeMachoObject;
export 'src/image/relocate.dart' show ImageError;
