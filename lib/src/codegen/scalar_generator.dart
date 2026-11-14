import 'dart:typed_data';
import 'dart:ffi' show Void, Int64;

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
import 'scalar_function.dart';
import 'native_adapter.dart';
import 'native_callback.dart';
import 'constant_data.dart';
import 'stack_maps.dart';
import 'heap_entry.dart';

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
    final persistent = prepared.persistent, cleanup = prepared.cleanup;
    final layouts = selection.layouts, heap = selection.heap;
    final globals = selection.globals, traces = selection.traces;
    final relocations = <Relocation>[];
    final symbolNames = <String, int>{};
    int nativeSymbol(String name) {
      prepared.checkNativeSymbol(name);
      return symbolNames.putIfAbsent(name, () => symbolNames.length);
    }

    final nativeCalls = <(int, Fixup, int)>[];
    final nativeAddresses = <(int, Fixup, int)>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    final callbackOwners = <NativeCallbackEntry, List<(int, Fixup)>>{};
    final callbackAddresses = <NativeCallbackEntry, List<(int, Fixup)>>{};
    final callbackTemplates = <(int, Fixup)>[];
    NativeCallback<R> callbackEntry(
      FunctionEmitter<R> emitter,
      NativeCallbackEntry callback,
    ) => NativeCallback(
      emitter,
      callback,
      (fixup) => (callbackOwners[callback] ??= []).add((code.length, fixup)),
    );
    final functions = {
      for (final body in selection.functions.values)
        body.target: ScalarFunction(body, _createFunction()),
    };
    final capture = selection.capture, managed = selection.managed;
    final primitives = selection.primitives;
    final indices = {
      for (final (i, declaration) in selected.indexed) declaration: i,
    };
    final hasRoots = managed || functions.values.any((f) => f.hasRoots);
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

    final globalAddresses = <(int, Fixup)>[],
        contextAddresses = <(int, Fixup)>[];
    final rootAddresses = <(int, Fixup)>[],
        errorAddresses = <(int, Fixup)>[],
        uncaughtAddresses = <(int, Fixup)>[];
    void call(Fixup fixup, FunctionTarget callee) {
      final index = indices[callee];
      if (index == null) {
        throw StateError('Unprepared call definition: ${callee.name}');
      }
      relocations.add(
        .instruction(0, code.length + fixup.offset, fixup.encoding, index),
      );
    }

    HeapEntry<R>? entry(FunctionEmitter<R> emitter) => !managed
        ? null
        : HeapEntry(
            emitter,
            heap.release,
            heap.isOutOfMemory,
            heap.runEvents,
            (fixup) => rootAddresses.add((code.length, fixup)),
            (fixup) => errorAddresses.add((code.length, fixup)),
            (fixup) => uncaughtAddresses.add((code.length, fixup)),
            call,
            (position) => safepoint(position, StackRoots(0, 0, [])),
            context: persistent
                ? (fixup) => contextAddresses.add((code.length, fixup))
                : null,
            globals: persistent && !globals.isEmpty
                ? (fixup) => globalAddresses.add((code.length, fixup))
                : null,
          );
    void codeAddress(Fixup fixup, int position) => maps.reference(
      code.length + fixup.offset,
      fixup.encoding,
      code.length + position,
    );
    Uint8List release(FunctionEmitter<R> emitter) {
      final destination = emitter.convention.classify(
        NativeSignature(Void, [Int64]),
      );
      final context = entry(emitter)!;
      final frame = context.frame(destination.stackBytes);
      emitter.prologue(frame);
      context.enter(frame);
      final argument =
          (destination.parameters.single as RegisterArgument<R>).register;
      emitter.move(argument, emitter.heapRegister);
      call(emitter.call(), heap.release);
      safepoint(emitter.position, StackRoots(0, 0, []));
      context.restoreCaller(frame);
      emitter.epilogue(frame);
      return emitter.finish();
    }

    for (final declaration in selected) {
      final source = functions[declaration]?.sourceTarget ?? declaration;
      frameSource = capture ? source : null;
      final binding = imports[declaration], export = exports[declaration];
      final exported = export != null && !needsEntry(export.signature);
      code.add(Uint8List((-code.length) & 15));
      final emitter = functions[declaration]?.emitter ?? _createFunction();
      final bytes = declaration == cleanup
          ? release(emitter)
          : declaration == globals.address
          ? globals.emitAddress(
              emitter,
              (fixup) => globalAddresses.add((code.length, fixup)),
            )
          : declaration == traces.capture
          ? traces.emit(emitter, call, safepoint)
          : layouts.nativeCalls.signatures.containsKey(declaration)
          ? NativeAdapter(emitter).generate(
              layouts.nativeCalls.signatures[declaration]!,
              (_, _, _) =>
                  throw StateError('Expected an indirect native call.'),
              intoDart: false,
              heap: entry(emitter),
              codeAddress: codeAddress,
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
          ? heap.emit(
              declaration,
              emitter,
              layouts,
              call,
              (fixup, type) {
                relocations.add(
                  .instruction(
                    0,
                    code.length + fixup.offset,
                    fixup.encoding,
                    constants.typeAddress(type),
                  ),
                );
              },
              (fixup, value) {
                relocations.add(
                  .instruction(
                    0,
                    code.length + fixup.offset,
                    fixup.encoding,
                    constants.addressOf(value),
                  ),
                );
              },
              safepoint,
              (fixup, position) {
                maps.reference(
                  code.length + fixup.offset,
                  fixup.encoding,
                  code.length + position,
                );
              },
              (fixup) {
                final symbol = nativeSymbol('.dartc.clock');
                nativeCalls.add((code.length, fixup, symbol));
              },
              (fixup) => callbackTemplates.add((code.length, fixup)),
            )
          : binding != null
          ? NativeAdapter(emitter).generate(
              binding.signature,
              (fixup, position, frame) {
                final symbol = nativeSymbol(
                  target.nativeSymbol(binding.symbol),
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
              },
              intoDart: false,
              heap: entry(emitter),
              codeAddress: codeAddress,
            )
          : functions[declaration]!.generate(
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
              failures: managed,
              persistent: persistent,
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
        heap: entry(emitter),
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
      final bytes = NativeAdapter(emitter).generate(
        value.signature,
        (fixup, position, frame) {
          call(fixup, key);
          safepoint(position, StackRoots(0, 0, []));
        },
        intoDart: true,
        heap: entry(emitter),
      );
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
      final context = entry(emitter);
      final frame = context?.frame(0);
      final exitCode = runtime?.processExitCode;
      final bytes = emitter.start(() {
        if (context != null) context.enter(frame!);
        final fixup = emitter.call();
        call(fixup, function);
        safepoint(emitter.position, StackRoots(0, 0, []));
        if (context != null) {
          context.leave(frame!, null, release: true, processExitCode: exitCode);
        } else if (exitCode != null) {
          call(emitter.call(), exitCode);
        }
        return exitCode == null
            ? null
            : emitter.convention
                  .classify(NativeSignature(Int64, []))
                  .resultRegister;
      }, frame);
      symbols.add(.new(symbol, 0, code.length, bytes.length));
      code.add(bytes);
    }
    final globalData = globals.isEmpty ? null : globals.initialData(layouts);
    final descriptor = globals.isEmpty
        ? null
        : constants.typeAddress(globals.declaration.type);
    final globalType = globals.isEmpty
        ? null
        : constants.addressOf(layouts.types.constant(globals.declaration.type));
    assert(symbols.length == constants.symbolBase);
    symbols.addAll(constants.symbols);
    final sections = [
      Section.code(code.takeBytes()),
      if (constants.symbols.isNotEmpty) constants.finish(),
    ];
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
    if (globalData != null) {
      final symbol = symbols.length, section = sections.length;
      symbols.add(
        Symbol(
          '.dartc.globals',
          section,
          0,
          globalData.length,
          kind: .data,
          binding: .local,
        ),
      );
      sections.add(Section.data(globalData, alignment: 8));
      relocations.addAll([
        Relocation.address(section, ObjectHeader.descriptorOffset, descriptor!),
        Relocation.address(section, ObjectHeader.typeOffset, globalType!),
      ]);
      for (final (start, fixup) in globalAddresses) {
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
    if (persistent) {
      final symbol = symbols.length;
      symbols.add(
        Symbol(
          '.dartc.heap',
          sections.length,
          0,
          RuntimeContext.size,
          kind: .data,
          binding: .local,
        ),
      );
      sections.add(Section.zeroFill(RuntimeContext.size, alignment: 8));
      for (final (start, fixup) in contextAddresses) {
        relocations.add(
          Relocation.instruction(
            0,
            start + fixup.offset,
            fixup.encoding,
            symbol,
          ),
        );
      }
      if (entryPoint == null) {
        relocations.add(
          Relocation.address(sections.length, 0, indices[cleanup]!),
        );
        sections.add(Section.finalizers(List.filled(8, 0)));
      }
    }
    final rootSymbol = maps.finish(sections, symbols, relocations);
    if (managed) {
      for (final (uses, name, message) in [
        (errorAddresses, '.dartc.oom', HeapEntry.message),
        (uncaughtAddresses, '.dartc.uncaught', HeapEntry.uncaughtMessage),
      ]) {
        for (final (start, fixup) in uses) {
          relocations.add(
            .instruction(
              0,
              start + fixup.offset,
              fixup.encoding,
              symbols.length,
            ),
          );
        }
        symbols.add(
          .new(
            name,
            sections.length,
            0,
            message.length,
            kind: .data,
            binding: .local,
          ),
        );
        sections.add(.readOnlyData(message.codeUnits));
      }
      for (final (start, fixup) in rootAddresses) {
        relocations.add(
          .instruction(0, start + fixup.offset, fixup.encoding, rootSymbol!),
        );
      }
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
