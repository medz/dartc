import 'dart:typed_data';
import 'dart:ffi' show Float;

import 'package:dartc/object.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';

import 'code_generator.dart';
import 'function_emitter.dart';
import 'scalar_function.dart';
import 'native_entry.dart';

/// Generates scalar modules with target-specific function emitters.
base class ScalarCodeGenerator<R extends Object>(
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
      final exported = export != null && !_needsEntry(export.signature);
      if (export != null &&
          (export.signature.parameters.length !=
                  declaration.parameterTypes.length ||
              declaration.returnType !=
                  FfiTypes.valueType(export.signature.result) ||
              declaration.parameterTypes.indexed.any(
                (p) =>
                    p.$2 !=
                    FfiTypes.valueType(export.signature.parameters[p.$1]),
              ))) {
        throw ArgumentError('Native signature mismatch: ${declaration.name}');
      }
      code.add(Uint8List((-code.length) & 15));
      final bytes = ScalarFunction(_createFunction())
          .generate(function, (fixup, callee) {
            final index = indices[callee];
            if (index == null) {
              throw ArgumentError('Missing call definition: ${callee.name}');
            }
            relocations.add(
              .new(0, code.length + fixup.offset, fixup.encoding, index),
            );
          });
      symbols.add(
        .new(
          exported ? target.nativeSymbol(export.symbol) : declaration.name,
          0,
          code.length,
          bytes.length,
          binding: exported ? .global : .local,
          exported: exported,
        ),
      );
      code.add(bytes);
    }
    for (final MapEntry(:key, :value) in exports.entries) {
      if (!_needsEntry(value.signature)) continue;
      code.add(Uint8List((-code.length) & 15));
      final bytes = NativeEntry(_createFunction()).generate(value.signature, (
        fixup,
      ) {
        relocations.add(
          .new(0, code.length + fixup.offset, fixup.encoding, indices[key]!),
        );
      });
      symbols.add(
        .new(
          target.nativeSymbol(value.symbol),
          0,
          code.length,
          bytes.length,
          binding: .global,
          exported: true,
        ),
      );
      code.add(bytes);
    }
    return .new(
      target,
      [Section.code(code.takeBytes())],
      symbols,
      relocations: relocations,
    );
  }

  bool _needsEntry(NativeSignature signature) => [
    signature.result,
    ...signature.parameters,
  ].any((t) => t == Float || (t.integerLayout?.bytes ?? 8) < 8);
}
