import 'package:dartc/lir.dart';
import 'package:dartc/src/emit/arm64/assembler.dart';
import 'package:dartc/src/emit/arm64/machine.dart';
import 'package:dartc/src/emit/liveness.dart';
import 'package:dartc/src/emit/selection.dart';

/// The live ranges of [function] for ARM64.
Liveness livenessOf(LirFunction function) =>
    Liveness(function, Selection(function, Arm64Machine(Arm64Assembler())));
