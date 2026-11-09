import 'package:dartc/assembler/arm64.dart' as arm64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';
import 'package:dartc/assembler/x64.dart' as x64;

ObjectModule functions(Target target, Map<String, int> values) {
  final code = <int>[], symbols = <Symbol>[];
  for (final MapEntry(:key, :value) in values.entries) {
    final List<int> body;
    if (target.architecture == .arm64) {
      final assembler = arm64.Assembler()
        ..loadImmediate(.x0, value)
        ..ret();
      body = assembler.finish();
    } else {
      final assembler = x64.Assembler()
        ..loadImmediate(.rax, value)
        ..ret();
      body = assembler.finish();
    }
    symbols.add(
      .new(
        target.operatingSystem == .macos ? '_$key' : key,
        code.length,
        body.length,
        exported: true,
      ),
    );
    code.addAll(body);
  }
  return .new(target, code, symbols);
}
