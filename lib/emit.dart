/// Machine code generation from the machine-level representation.
library;

export 'src/emit/code.dart';
export 'src/emit/emit.dart' show emitArm64;
export 'src/emit/stack_maps.dart' show StackMap, ThrowTarget;
