import 'dart:ffi' show Abi;

import 'native_signature.dart';
import 'c_identifier.dart';

/// An explicitly named native function, independent of its Dart declaration.
final class NativeExport(final String symbol, final NativeSignature signature) {
  this {
    checkCIdentifier(symbol);
  }

  /// Writes a C prototype retaining scalar, pointer and native function types.
  ///
  /// [abi] selects storage for ABI-specific integers in the signature.
  /// [typeNames] supplies the C tags selected for a complete header.
  void writeDeclaration(
    StringSink output, {
    Abi? abi,
    Map<NativeTypeRef, String> typeNames = const {},
  }) {
    output.writeln(
      '${signature.declaration(symbol, abi: abi, typeNames: typeNames)};',
    );
  }
}
