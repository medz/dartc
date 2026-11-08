import 'package:dartc/abi.dart';
import 'package:dartc/arm64.dart' as arm64;
import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart' as x64;

ObjectFile aliases(Target target) => switch (target.architecture) {
  .arm64 => _functions(target, Arm64Abi(arm64.Assembler())),
  .x64 => _functions(target, X64Abi(x64.Assembler())),
};

ObjectFile _functions<R>(Target target, IntegerAbi<R> abi) {
  final bytes = <int>[], symbols = <Symbol>[];
  for (final subtract in [false, true]) {
    final left = abi.parameters[0], right = abi.parameters[1];
    if (subtract) {
      abi.subtract(right, left, right);
    } else {
      abi.add(right, left, right);
    }
    abi.returnValue(right);
    final code = abi.takeBytes();
    final name = subtract ? 'alias_subtract' : 'alias_add';
    symbols.add(
      .new(
        target.operatingSystem == .macos ? '_$name' : name,
        bytes.length,
        code.length,
      ),
    );
    bytes.addAll(code);
  }
  return .new(target, bytes, symbols);
}
