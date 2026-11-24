/// The Dart-level program representation, with its checker and interpreter.
library;

export 'src/hir/block.dart';
export 'src/hir/class.dart';
export 'src/hir/copy.dart';
export 'src/hir/coroutine.dart';
export 'src/hir/global.dart' show HirConstObject, HirGlobal;
export 'src/hir/instruction.dart';
export 'src/hir/interpret.dart' show HirInterpreter;
export 'src/hir/machine.dart';
export 'src/hir/module.dart';
export 'src/hir/print.dart' show printHir;
export 'src/hir/simulate.dart' show formatExactly;
export 'src/hir/value.dart';
export 'src/hir/verify.dart' show HirError, verifyHir;
