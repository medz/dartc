import 'dart:typed_data';
import 'dart:ffi' show Int64;

import 'package:dartc/object.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/runtime/contracts.dart' show NativeCallbackLayout;

import 'code_generator.dart';
import 'program_preparation.dart';
import 'function_emitter.dart';
import 'function_allocation.dart';
import 'function_selection.dart';
import 'scalar_function.dart';
import 'memory_function.dart';
import 'heap_runtime.dart';
import 'native_adapter.dart';
import 'native_callback.dart';
import 'constant_data.dart';
import 'stack_maps.dart';

/// Generates native modules with target-specific function emitters.
base class ScalarCodeGenerator<R extends Object>(
  @override final Target target,
  FunctionEmitter<R> Function() createFunction,
) implements CodeGenerator {
  final FunctionEmitter<R> Function() _createFunction = createFunction;

  @override
  ObjectModule generate(PreparedProgram prepared) {
    prepared.checkTarget(target);
    final selection = prepared.selection;
    final selected = prepared.definitions;
    final imports = prepared.imports, exports = prepared.exports;
    final callbacks = prepared.callbacks;
    final callbackGetters = {
      for (final entry in callbacks.entries) entry.value.address: entry.key,
    };
    final nativeSymbols = prepared.nativeSymbols;
    final entryPoint = prepared.entryPoint, runtime = prepared.runtime;
    final cleanup = prepared.cleanup;
    final layouts = selection.layouts, heap = selection.heap;
    final relocations = <Relocation>[];
    final symbolNames = <String, int>{};
    int nativeSymbol(String name) {
      prepared.checkNativeSymbol(name);
      return symbolNames.putIfAbsent(name, () => symbolNames.length);
    }

    final nativeCalls = <(int, Fixup, int)>[];
    final nativeAddresses = <(int, Fixup, int)>[];
    final nativeDataAddresses = <NativeData, List<(int, Fixup)>>{};
    final moduleObjectAddresses = <ModuleObject, List<(int, Fixup)>>{};
    final moduleRootAddresses = <(int, Fixup)>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    final callbackOwners = <NativeCallbackTarget, List<(int, Fixup)>>{};
    final callbackAddresses = <NativeCallbackTarget, List<(int, Fixup)>>{};
    final callbackTemplates = <(int, Fixup)>[];
    NativeCallback<R> callbackEntry(
      FunctionEmitter<R> emitter,
      NativeCallbackTarget callback,
    ) => NativeCallback(
      emitter,
      callback,
      (fixup) => (callbackOwners[callback] ??= []).add((code.length, fixup)),
    );
    final constraints = _createFunction();
    final functions = {
      for (final body in selection.functions.values)
        body.target: FunctionSelection(body, constraints),
    };
    final capture = selection.capture, managed = selection.managed;
    final primitives = selection.primitives;
    final indices = {
      for (final (i, declaration) in selected.indexed) declaration: i,
    };
    final addressesStackMaps = functions.values.any(
      (function) => function.body.instructions.values
          .expand((values) => values)
          .any((value) => value is StackMapAddress),
    );
    final hasRoots =
        managed ||
        addressesStackMaps ||
        functions.values.any(
          (function) =>
              function.liveReferences.values.any((roots) => roots.isNotEmpty),
        );
    bool needsEntry(NativeSignature signature) =>
        hasRoots || _needsEntry(signature);
    final maps = StackMaps();
    final constants = ConstantData(
      layouts,
      selected.length +
          callbacks.length +
          exports.values.where((e) => needsEntry(e.signature)).length +
          (entryPoint == null ? 0 : 1),
      stackTraces: capture,
      stackContext: runtime?.stackContext,
      functionSymbols: indices,
    );
    FunctionTarget? frameSource;
    void safepoint(
      int position,
      StackRoots roots, [
      SourceLocation? location,
      int? context,
    ]) {
      if (hasRoots) {
        final description = frameSource == null
            ? null
            : constants.frameAddress(frameSource, location);
        maps.add(code.length + position, roots, description, context);
      }
    }

    final rootAddresses = <(int, Fixup)>[];
    void call(Fixup fixup, FunctionTarget callee) {
      final index = indices[callee];
      if (index == null) {
        throw StateError('Unprepared call definition: ${callee.name}');
      }
      relocations.add(
        .instruction(0, code.length + fixup.offset, fixup.encoding, index),
      );
    }

    void codeAddress(Fixup fixup, int position) => maps.reference(
      code.length + fixup.offset,
      fixup.encoding,
      code.length + position,
    );
    for (final declaration in selected) {
      final source = functions[declaration]?.body.sourceTarget ?? declaration;
      frameSource = capture ? source : null;
      final binding = imports[declaration], export = exports[declaration];
      final exported = export != null && !needsEntry(export.signature);
      code.add(Uint8List((-code.length) & 15));
      final emitter = _createFunction();
      final bytes = layouts.nativeCalls.entries.containsKey(declaration)
          ? NativeAdapter(emitter).generate(
              layouts.nativeCalls.entries[declaration]!.signature,
              (_, _, _) =>
                  throw StateError('Expected an indirect native call.'),
              intoDart: false,
              indirectCall: (position, frame) => safepoint(
                position,
                StackRoots(
                  frame.incomingStackOffset,
                  frame.returnAddressOffset,
                  [],
                ),
              ),
            )
          : callbackGetters.containsKey(declaration)
          ? callbackEntry(emitter, callbackGetters[declaration]!).address(
              (fixup) =>
                  (callbackAddresses[callbackGetters[declaration]!] ??= []).add(
                    (code.length, fixup),
                  ),
            )
          : primitives.contains(declaration)
          ? MemoryFunction(
              declaration == heap.invalid
                  ? MemoryPrimitive.fail
                  : heap.runtime!.primitives[declaration]!,
              emitter,
            ).generate((fixup) {
              final symbol = nativeSymbol('.dartc.clock');
              nativeCalls.add((code.length, fixup, symbol));
            }, (fixup) => callbackTemplates.add((code.length, fixup)))
          : binding != null
          ? NativeAdapter(emitter).generate(binding.signature, (
              fixup,
              position,
              frame,
            ) {
              final symbol = nativeSymbol(target.nativeSymbol(binding.symbol));
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
          : ScalarFunction(
              FunctionAllocation(
                functions[declaration] ??
                    (throw StateError(
                      'Prepared definition has no emission: '
                      '${declaration.library}::${declaration.name}',
                    )),
              ),
              emitter,
            ).generate(
              call,
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
              failures: managed || selection.failures,
              callableTable: constants.callableTable,
              constantSymbol: (fixup, symbol) {
                relocations.add(
                  .instruction(
                    0,
                    code.length + fixup.offset,
                    fixup.encoding,
                    symbol,
                  ),
                );
              },
              stackMapAddress: (fixup) =>
                  rootAddresses.add((code.length, fixup)),
              moduleRootsAddress: (fixup) =>
                  moduleRootAddresses.add((code.length, fixup)),
              moduleObjectAddress: (fixup, declaration) {
                (moduleObjectAddresses[declaration] ??= []).add((
                  code.length,
                  fixup,
                ));
              },
              descriptorAddress: (fixup, type) {
                relocations.add(
                  .instruction(
                    0,
                    code.length + fixup.offset,
                    fixup.encoding,
                    constants.typeAddress(type),
                  ),
                );
              },
              nativeAddress: (fixup, reference) {
                final name = nativeSymbols[reference];
                if (name == null) {
                  throw StateError(
                    'Unprepared native address: ${reference.symbol}',
                  );
                }
                final symbol = nativeSymbol(target.nativeSymbol(name));
                nativeAddresses.add((code.length, fixup, symbol));
              },
              nativeDataAddress: (fixup, declaration) {
                (nativeDataAddresses[declaration] ??= []).add((
                  code.length,
                  fixup,
                ));
              },
              codeAddress: codeAddress,
            );
      symbols.add(
        .new(
          exported
              ? target.nativeSymbol(export.symbol)
              : declaration.name.isEmpty
              ? '.function${symbols.length}'
              : declaration.name,
          0,
          code.length,
          bytes.length,
          binding: exported ? .global : .local,
          exported: exported,
        ),
      );
      code.add(bytes);
    }
    frameSource = null;
    for (final callback in callbacks.entries) {
      code.add(Uint8List((-code.length) & 15));
      final emitter = _createFunction();
      final bytes = NativeAdapter(emitter).generate(
        callback.key.signature,
        (fixup, position, frame) {
          call(fixup, callback.value.target);
          safepoint(position, StackRoots(0, 0, []));
        },
        intoDart: true,
        callback: callbackEntry(emitter, callback.key),
      );
      for (final (start, fixup)
          in callbackAddresses[callback.key] ?? const <(int, Fixup)>[]) {
        relocations.add(
          .instruction(0, start + fixup.offset, fixup.encoding, symbols.length),
        );
      }
      symbols.add(
        .new(
          '.callback${symbols.length}',
          0,
          code.length,
          bytes.length,
          binding: .local,
        ),
      );
      code.add(bytes);
    }
    for (final MapEntry(:key, :value) in exports.entries) {
      if (!needsEntry(value.signature)) continue;
      code.add(Uint8List((-code.length) & 15));
      final emitter = _createFunction();
      final bytes = NativeAdapter(emitter)
          .generate(value.signature, (fixup, position, frame) {
            call(fixup, key);
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
      code.add(Uint8List((-code.length) & 15));
      final emitter = _createFunction();
      final bytes = emitter.start(() {
        call(emitter.call(), function);
        safepoint(emitter.position, StackRoots(0, 0, []));
        return function.returnType == ValueType.integer
            ? emitter.convention
                  .classify(NativeSignature(Int64, []))
                  .resultRegister
            : null;
      }, null);
      symbols.add(.new(symbol, 0, code.length, bytes.length));
      code.add(bytes);
    }
    final moduleObjects = {
      for (final declaration in moduleObjectAddresses.keys)
        declaration: constants.moduleObjectData(declaration),
    };
    assert(symbols.length == constants.symbolBase);
    symbols.addAll(constants.symbols);
    final sections = [
      Section.code(code.takeBytes()),
      if (constants.symbols.isNotEmpty) constants.finish(),
    ];
    final moduleSymbols = <int>[];
    if (moduleObjects.isNotEmpty) {
      final bytes = BytesBuilder(copy: false);
      final section = sections.length;
      for (final MapEntry(key: declaration, value: image)
          in moduleObjects.entries) {
        final symbol = symbols.length;
        final offset = bytes.length;
        moduleSymbols.add(symbol);
        symbols.add(
          Symbol(
            '.dartc.object$symbol',
            section,
            offset,
            image.bytes.length,
            kind: .data,
            binding: .local,
          ),
        );
        bytes.add(image.bytes);
        for (final reference in image.references) {
          relocations.add(
            Relocation.address(
              section,
              offset + reference.offset,
              reference.symbol,
            ),
          );
        }
        for (final (start, fixup) in moduleObjectAddresses[declaration]!) {
          relocations.add(
            Relocation.instruction(
              0,
              start + fixup.offset,
              fixup.encoding,
              symbol,
            ),
          );
        }
      }
      sections.add(Section.data(bytes.takeBytes(), alignment: 8));
    }
    if (moduleRootAddresses.isNotEmpty) {
      final table = symbols.length;
      final section = sections.length;
      final data = ByteData(
        ModuleRootTable.entries +
            moduleSymbols.length * ModuleRootTable.entrySize,
      );
      data.setUint64(
        ModuleRootTable.count,
        moduleSymbols.length,
        target.byteOrder,
      );
      symbols.add(
        Symbol(
          '.dartc.moduleRoots',
          section,
          0,
          data.lengthInBytes,
          kind: .data,
          binding: .local,
        ),
      );
      for (final (index, symbol) in moduleSymbols.indexed) {
        relocations.add(
          Relocation.address(
            section,
            ModuleRootTable.entries + index * ModuleRootTable.entrySize,
            symbol,
          ),
        );
      }
      for (final (start, fixup) in moduleRootAddresses) {
        relocations.add(
          Relocation.instruction(
            0,
            start + fixup.offset,
            fixup.encoding,
            table,
          ),
        );
      }
      sections.add(
        Section.readOnlyData(data.buffer.asUint8List(), alignment: 8),
      );
    }
    final nativeDataGroups = <SectionKind, List<NativeData>>{};
    for (final data in nativeDataAddresses.keys) {
      final kind = !data.writable
          ? SectionKind.readOnlyData
          : data.bytes.every((byte) => byte == 0)
          ? SectionKind.zeroFill
          : SectionKind.data;
      (nativeDataGroups[kind] ??= []).add(data);
    }
    for (final MapEntry(key: kind, value: declarations)
        in nativeDataGroups.entries) {
      final content = BytesBuilder(copy: false);
      var size = 0, alignment = 1;
      for (final data in declarations) {
        final padding = (-size) & (data.alignment - 1);
        size += padding;
        if (data.alignment > alignment) alignment = data.alignment;
        final symbol = symbols.length;
        for (final (start, fixup) in nativeDataAddresses[data]!) {
          relocations.add(
            .instruction(0, start + fixup.offset, fixup.encoding, symbol),
          );
        }
        symbols.add(
          Symbol(
            '.dartc.data$symbol',
            sections.length,
            size,
            data.bytes.length,
            kind: .data,
            binding: .local,
          ),
        );
        if (kind != .zeroFill) {
          content.add(Uint8List(padding));
          content.add(data.bytes);
        }
        size += data.bytes.length;
      }
      sections.add(switch (kind) {
        .readOnlyData => Section.readOnlyData(
          content.takeBytes(),
          alignment: alignment,
        ),
        .data => Section.data(content.takeBytes(), alignment: alignment),
        .zeroFill => Section.zeroFill(size, alignment: alignment),
        _ => throw StateError('Invalid native data section.'),
      });
    }
    if (callbackTemplates.isNotEmpty) {
      final trampoline = _createFunction().callbackTrampoline();
      final page = Uint8List(NativeCallbackLayout.pageBytes);
      for (var at = 0; at < page.length; at += trampoline.length) {
        page.setRange(at, at + trampoline.length, trampoline);
      }
      for (final (start, fixup) in callbackTemplates) {
        relocations.add(
          .instruction(0, start + fixup.offset, fixup.encoding, symbols.length),
        );
      }
      symbols.add(
        .new(
          '.callbackTemplate',
          sections.length,
          0,
          page.length,
          binding: .local,
        ),
      );
      sections.add(
        Section.code(
          page,
          alignment: target.operatingSystem == .macos
              ? target.architecture == .arm64
                    ? 16384
                    : 4096
              : NativeCallbackLayout.pageBytes,
        ),
      );
    }
    for (final uses in callbackOwners.values) {
      for (final (start, fixup) in uses) {
        relocations.add(
          .instruction(0, start + fixup.offset, fixup.encoding, symbols.length),
        );
      }
      symbols.add(
        .new(
          '.callbackThread${symbols.length}',
          sections.length,
          0,
          8,
          kind: .data,
          binding: .local,
        ),
      );
      sections.add(Section.zeroFill(8, alignment: 8));
    }
    if (cleanup != null) {
      relocations.add(
        Relocation.address(sections.length, 0, indices[cleanup]!),
      );
      sections.add(Section.finalizers(List.filled(8, 0)));
    }
    final rootSymbol = maps.finish(
      sections,
      symbols,
      relocations,
      required: rootAddresses.isNotEmpty,
    );
    for (final (start, fixup) in rootAddresses) {
      relocations.add(
        .instruction(0, start + fixup.offset, fixup.encoding, rootSymbol!),
      );
    }
    return .new(
      target,
      sections,
      symbols,
      imports: symbolNames.keys,
      relocations: [
        ...relocations,
        ...constants.relocations,
        for (final (start, fixup, symbol) in nativeAddresses)
          Relocation.instruction(
            0,
            start + fixup.offset,
            fixup.encoding,
            symbols.length + symbol,
            indirect: true,
          ),
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

  bool _needsEntry(NativeSignature signature) =>
      signature.variadicStart != null ||
      [signature.result, ...signature.parameters].any(
        (t) =>
            t is NativeCompoundType ||
            t.isSinglePrecision ||
            (t.resolveAbi(target.abi).integerLayout?.bytes ?? 8) < 8,
      );
}
