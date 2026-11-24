import 'convention.dart';
import 'passing_arm64.dart';
import 'passing_x64.dart';
import 'target.dart';
import 'types.dart';

/// How the values of a call are passed.
typedef CallPassing = ({
  List<Passing> parameters,
  Passing result,
  int stackBytes,
});

/// How functions with [signature] are called on [target].
CallPassing passingOf(NativeSignature signature, Target target) {
  final convention = switch (target) {
    .macosArm64 => Arm64Passing(isApple: true),
    .linuxArm64 => Arm64Passing(isApple: false),
    .linuxX64 => X64Passing(),
  };
  // Where a result goes may be passed before the parameters.
  final result = convention.result(signature.result);
  final parameters = [
    for (final (i, type) in signature.parameters.indexed)
      signature.isVariable(i)
          ? convention.variable(type)
          : convention.parameter(type),
  ];
  return (
    parameters: parameters,
    result: result,
    stackBytes: alignTo(convention.stackEnd, 16),
  );
}
