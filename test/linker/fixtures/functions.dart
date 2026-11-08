import 'package:dartc/arm64.dart' as arm64;
import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart' as x64;

ObjectFile functions(Target target, Map<String, int> values) {
  final code = <int>[], symbols = <Symbol>[];
  for (final MapEntry(:key, :value) in values.entries) {
    final List<int> body;
    if (target.architecture == .arm64) {
      final assembler = arm64.Assembler()
        ..loadImmediate(.x0, value)
        ..ret();
      body = assembler.takeBytes();
    } else {
      final assembler = x64.Assembler()
        ..loadImmediate(.rax, value)
        ..ret();
      body = assembler.takeBytes();
    }
    symbols.add(
      .new(
        target.operatingSystem == .macos ? '_$key' : key,
        code.length,
        body.length,
      ),
    );
    code.addAll(body);
  }
  return .new(target, code, symbols);
}
