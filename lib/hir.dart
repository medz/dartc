/// The Dart-level program representation, with its checker and interpreter.
library;

export 'src/hir/instruction.dart';
export 'src/hir/interpret.dart' show HirInterpreter;
export 'src/hir/module.dart';
export 'src/hir/print.dart' show printHir;
export 'src/hir/verify.dart' show HirError, verifyHir;
