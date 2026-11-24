/// Compilation from Dart source to native programs and libraries.
library;

export 'package:dartc/driver.dart'
    show
        CompileOptions,
        LibraryKind,
        compileLibrary,
        compileProgram,
        hostTarget,
        writeOutput,
        writeProgram;
export 'package:dartc/native.dart' show Architecture, OperatingSystem, Target;
export 'package:dartc/optimize.dart' show Optimization;
export 'package:dartc/source.dart' show CompileFailure, SourceProblem;
