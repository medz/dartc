import 'native_export.dart';

/// Native function declarations with distinct exported names.
final class NativeExports(Iterable<NativeExport> functions) {
  /// Native functions in declaration order.
  final List<NativeExport> functions = .unmodifiable(functions);

  this {
    final names = <String>{};
    for (final function in this.functions) {
      if (!names.add(function.symbol)) {
        throw ArgumentError('Repeated native export: ${function.symbol}');
      }
    }
  }

  /// Writes declarations usable from both C and C++.
  void writeHeader(StringSink output) {
    output.writeln(
      '#pragma once\n#include <stdint.h>\n\n#ifdef __cplusplus\nextern "C" {\n#endif\n',
    );
    for (final function in functions) {
      function.writeDeclaration(output);
    }
    output.writeln('\n#ifdef __cplusplus\n}\n#endif');
  }
}
