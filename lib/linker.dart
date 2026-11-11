/// Links native code artifacts without an external toolchain.
library;

export 'src/linker/linker.dart' show Linker;
export 'src/linker/input.dart'
    show LinkInput, ObjectInput, ArchiveInput, SharedLibraryInput;
export 'src/linker/elf/linker.dart' show ElfLinker;
export 'src/linker/mach_o/linker.dart' show MachOLinker;
export 'src/linker/executable_resources.dart' show ExecutableResources;
