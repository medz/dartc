import 'native_signature.dart';
import 'c_identifier.dart';

/// An explicitly named native function, independent of its Dart declaration.
final class NativeExport(final String symbol, final NativeSignature signature) {
  this {
    checkCIdentifier(symbol);
  }

  /// Writes a C prototype retaining scalar, pointer and native function types.
  void writeDeclaration(StringSink output) {
    output.writeln('${signature.declaration(symbol)};');
  }
}
