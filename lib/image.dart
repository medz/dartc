/// Executable files, libraries and object files from emitted machine code.
library;

export 'src/image/archive.dart' show writeArchive;
export 'src/image/elf.dart' show linkElf, linkElfLibrary;
export 'src/image/macho.dart' show linkMacho, linkMachoLibrary;
export 'src/image/macho_object.dart' show writeMachoObject;
export 'src/image/relocate.dart' show ImageError;
