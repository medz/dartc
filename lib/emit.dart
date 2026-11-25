/// Machine code generation from the machine-level representation.
library;

export 'src/emit/code.dart';
export 'src/emit/emit.dart' show emitCode, linuxEntrySymbol;
export 'src/emit/stack_maps.dart' show StackMap, ThrowTarget;
export 'src/emit/unsupported.dart';
