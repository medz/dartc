import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';

import 'code_generator.dart';
import 'function_emitter.dart';
import 'integer_function.dart';

/// Generates integer modules with target-specific function emitters.
base class IntegerCodeGenerator<R extends Object>(
  @override final Target target,
  FunctionEmitter<R> Function() createFunction,
) implements CodeGenerator {
  final FunctionEmitter<R> Function() _createFunction = createFunction;

  @override
  ObjectModule generate(
    IrProgram program, {
    required Iterable<FunctionTarget> definitions,
    Map<FunctionTarget, NativeExport> exports = const {},
  }) {
    final selected = definitions.toSet();
    if (selected.isEmpty || !selected.containsAll(exports.keys)) {
      throw ArgumentError('Expected definitions containing every export.');
    }
    final indices = {
      for (final (i, declaration) in selected.indexed) declaration: i,
    };
    final relocations = <Relocation>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    for (final declaration in selected) {
      final function = program.implementationOf(declaration);
      if (function is! IrFunction) {
        throw ArgumentError('Definition has no body: ${declaration.name}');
      }
      final export = exports[declaration];
      if (export != null &&
          (export.signature.parameterCount !=
                  declaration.parameterTypes.length ||
              declaration.returnType != .integer ||
              declaration.parameterTypes.any((type) => type != .integer))) {
        throw ArgumentError('Native signature mismatch: ${declaration.name}');
      }
      code.add(Uint8List((-code.length) & 15));
      final bytes = IntegerFunction(_createFunction())
          .generate(function, (offset, callee) {
            final index = indices[callee];
            if (index == null) {
              throw ArgumentError('Missing call definition: ${callee.name}');
            }
            relocations.add(
              .new(
                code.length + offset,
                target.architecture == .arm64 ? .arm64Call26 : .x64Call32,
                index,
              ),
            );
          });
      symbols.add(
        .new(
          export == null
              ? declaration.name
              : target.nativeSymbol(export.symbol),
          code.length,
          bytes.length,
          binding: export == null ? .local : .global,
          exported: export != null,
        ),
      );
      code.add(bytes);
    }
    return .new(target, code.takeBytes(), symbols, relocations: relocations);
  }
}
