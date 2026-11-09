/// Builds native programs and libraries from checked Dart declarations.
library;

export 'src/compiler/compiler.dart' show Compiler, Compilation;
export 'src/compiler/output.dart'
    show
        Output,
        ExecutableOutput,
        ObjectOutput,
        StaticLibraryOutput,
        SharedLibraryOutput;
