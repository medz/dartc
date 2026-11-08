import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';

import 'code_generator.dart';
import 'function_emitter.dart';
import 'integer_function.dart';

/// Generates independent integer functions with target-specific emitters.
base class IntegerCodeGenerator<R extends Object>(
  @override final Target target,
  FunctionEmitter<R> Function() createFunction,
) implements CodeGenerator {
  final FunctionEmitter<R> Function() _createFunction = createFunction;

  @override
  ObjectFile generate(IrProgram program, Map<FunctionTarget, String> exports) {
    if (exports.isEmpty) throw ArgumentError('No native exports.');
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    for (final MapEntry(key: declaration, value: name) in exports.entries) {
      final function = program.implementationOf(declaration);
      if (function is! IrFunction) {
        throw ArgumentError('Export has no body: $name');
      }
      final bytes = IntegerFunction(_createFunction()).generate(function);
      code.add(Uint8List((-code.length) & 15));
      symbols.add(.new(name, code.length, bytes.length));
      code.add(bytes);
    }
    return .new(target, code.takeBytes(), symbols);
  }
}
