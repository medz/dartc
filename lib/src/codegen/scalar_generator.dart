import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';

import 'code_generator.dart';
import 'function_emitter.dart';
import 'scalar_function.dart';
import 'native_adapter.dart';
import 'program_layout.dart';
import 'constant_data.dart';
import 'stack_maps.dart';

/// Generates native modules with target-specific function emitters.
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
    Map<FunctionTarget, NativeImport> imports = const {},
    ({FunctionTarget function, String symbol})? entryPoint,
  }) {
    final selected = definitions.toSet();
    if (selected.isEmpty ||
        !selected.containsAll([...exports.keys, ...imports.keys]) ||
        exports.keys.any(imports.containsKey)) {
      throw ArgumentError(
        'Expected distinct exports and imports in definitions.',
      );
    }
    final indices = {
      for (final (i, declaration) in selected.indexed) declaration: i,
    };
    final relocations = <Relocation>[];
    final nativeSymbols = <String, int>{};
    final nativeCalls = <(int, Fixup, int)>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    final layouts = ProgramLayout(program);
    final functions = <FunctionTarget, ScalarFunction<R>>{};
    for (final declaration in selected) {
      final function = program.implementationOf(declaration);
      final binding = imports[declaration];
      if (binding != null) {
        if (function is! IrExternal ||
            declaration.kind.hasReceiver ||
            declaration.typeParameters.isNotEmpty ||
            !FfiTypes.canCall(binding.signature, declaration.signature)) {
          throw ArgumentError(
            'Native import requires a matching external declaration: ${declaration.name}',
          );
        }
      } else if (function is! IrFunction) {
        throw ArgumentError('Definition has no body: ${declaration.name}');
      } else {
        functions[declaration] = ScalarFunction(
          function,
          _createFunction(),
          layouts,
        );
      }
      final export = exports[declaration];
      if (export != null && !_matches(declaration, export.signature)) {
        throw ArgumentError('Native signature mismatch: ${declaration.name}');
      }
    }
    final hasRoots = functions.values.any((f) => f.hasRoots);
    bool needsEntry(NativeSignature signature) =>
        hasRoots || _needsEntry(signature);
    final maps = StackMaps();
    void safepoint(int position, StackRoots roots) {
      if (hasRoots) maps.add(code.length + position, roots);
    }

    final constants = ConstantData(
      layouts,
      selected.length +
          exports.values.where((e) => needsEntry(e.signature)).length +
          (entryPoint == null ? 0 : 1),
    );
    for (final declaration in selected) {
      final binding = imports[declaration], export = exports[declaration];
      final exported = export != null && !needsEntry(export.signature);
      code.add(Uint8List((-code.length) & 15));
      final bytes = binding != null
          ? NativeAdapter(_createFunction())
                .generate(binding.signature, (fixup, position, frame) {
                  final symbol = nativeSymbols.putIfAbsent(
                    target.nativeSymbol(binding.symbol),
                    () => nativeSymbols.length,
                  );
                  nativeCalls.add((code.length, fixup, symbol));
                  safepoint(
                    position,
                    StackRoots(
                      frame.incomingStackOffset,
                      frame.returnAddressOffset,
                      [],
                    ),
                  );
                }, intoDart: false)
          : functions[declaration]!.generate(
              (fixup, callee) {
                final index = indices[callee];
                if (index == null) {
                  throw ArgumentError(
                    'Missing call definition: ${callee.name}',
                  );
                }
                relocations.add(
                  .instruction(
                    0,
                    code.length + fixup.offset,
                    fixup.encoding,
                    index,
                  ),
                );
              },
              (fixup, constant) {
                relocations.add(
                  .instruction(
                    0,
                    code.length + fixup.offset,
                    fixup.encoding,
                    constants.addressOf(constant),
                  ),
                );
              },
              safepoint,
            );
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
      if (!needsEntry(value.signature)) continue;
      code.add(Uint8List((-code.length) & 15));
      final bytes = NativeAdapter(_createFunction())
          .generate(value.signature, (fixup, position, frame) {
            relocations.add(
              .instruction(
                0,
                code.length + fixup.offset,
                fixup.encoding,
                indices[key]!,
              ),
            );
            safepoint(position, StackRoots(0, 0, []));
          }, intoDart: true);
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
    if (entryPoint case (:final function, :final symbol)) {
      final body = program.implementationOf(function);
      if (!selected.contains(function) ||
          body is! IrFunction ||
          body.bodyKind != .synchronous ||
          function.kind != .function ||
          function.parameterTypes.isNotEmpty ||
          function.typeParameters.isNotEmpty) {
        throw UnsupportedError(
          'Process entry requires a synchronous, parameterless function.',
        );
      }
      code.add(Uint8List((-code.length) & 15));
      final emitter = _createFunction();
      final bytes = emitter.start((fixup) {
        relocations.add(
          .instruction(
            0,
            code.length + fixup.offset,
            fixup.encoding,
            indices[function]!,
          ),
        );
        safepoint(emitter.position, StackRoots(0, 0, []));
      });
      symbols.add(.new(symbol, 0, code.length, bytes.length));
      code.add(bytes);
    }
    symbols.addAll(constants.symbols);
    final sections = [
      Section.code(code.takeBytes()),
      if (constants.symbols.isNotEmpty) constants.finish(),
    ];
    maps.finish(sections, symbols, relocations);
    return .new(
      target,
      sections,
      symbols,
      imports: nativeSymbols.keys,
      relocations: [
        ...relocations,
        ...constants.relocations,
        for (final (start, fixup, symbol) in nativeCalls)
          Relocation.instruction(
            0,
            start + fixup.offset,
            fixup.encoding,
            symbols.length + symbol,
          ),
      ],
    );
  }

  bool _matches(FunctionTarget declaration, NativeSignature signature) =>
      signature.parameters.length == declaration.parameterTypes.length &&
      declaration.returnType == FfiTypes.valueType(signature.result) &&
      declaration.parameterTypes.indexed.every(
        (p) => p.$2 == FfiTypes.valueType(signature.parameters[p.$1]),
      );

  bool _needsEntry(NativeSignature signature) => [
    signature.result,
    ...signature.parameters,
  ].any((t) => t.isSinglePrecision || (t.integerLayout?.bytes ?? 8) < 8);
}
