import 'dart:typed_data';
import 'dart:ffi' show Void, Int64;

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
import 'heap_plan.dart';
import 'heap_entry.dart';
import 'heap_functions.dart';
import 'frame_lookup.dart';
import 'stack_traces.dart';
import 'checked_casts.dart';
import 'member_calls.dart';
import 'numeric_operations.dart';
import 'global_storage.dart';

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
    final frames = FrameLookup();
    final traces = StackTraces(frames);
    final casts = CheckedCasts();
    IrCallable? constructor(ValueType type) {
      final target = program.classes
          .where((c) => c.type == type)
          .firstOrNull
          ?.constructors['new'];
      return target == null ? null : program.implementationOf(target);
    }

    final sourceProgram = program;
    final sourceDefinitions = {...selected};
    final lateErrorType = program.classes
        .where(
          (declaration) =>
              declaration.type.library == Uri.parse('dart:_internal') &&
              declaration.type.name == 'LateError',
        )
        .firstOrNull
        ?.type;
    late NumericOperations arithmetic;
    late GlobalStorage globals;
    // Helpers can reach SDK bodies with further globals or numeric operations.
    // Close those dependencies before fixing the holder and its physical layout.
    while (true) {
      final bodies = sourceDefinitions
          .map(sourceProgram.implementationOf)
          .whereType<IrFunction>();
      arithmetic = NumericOperations(
        bodies,
        argumentError: constructor(.argumentError),
        unsupportedError: constructor(.unsupportedError),
      );
      globals = GlobalStorage(
        bodies,
        lateError: lateErrorType == null ? null : constructor(lateErrorType),
      );
      if (arithmetic.functions.isEmpty && globals.isEmpty) break;
      final helpers = [...arithmetic.functions, ...globals.functions];
      final expanded = IrProgram(
        [
          ...sourceProgram.classes,
          if (!globals.isEmpty) globals.declaration,
          for (final declaration in arithmetic.classes)
            if (!sourceProgram.classes.any((c) => c.type == declaration.type))
              declaration,
        ],
        [...sourceProgram.functions, ...helpers],
        globals: sourceProgram.globals,
        externals: [
          ...sourceProgram.externals,
          if (!globals.isEmpty) IrExternal(globals.address),
        ],
      );
      final required = expanded.reachableFrom([
        ...sourceDefinitions,
        for (final function in helpers) function.target,
      ]);
      final discovered = required
          .where(
            (target) =>
                sourceProgram.implementationOf(target) != null &&
                !sourceDefinitions.contains(target),
          )
          .toList();
      if (discovered.isEmpty) {
        program = expanded;
        selected
          ..clear()
          ..addAll(required);
        break;
      }
      sourceDefinitions.addAll(discovered);
    }
    final layouts = ProgramLayout(
      [...casts.classes, ...program.classes, traces.declaration],
      referencedClasses: selected.expand(
        (target) =>
            program.implementationOf(target)?.referencedClasses ?? const [],
      ),
    );
    final persistent = !globals.isEmpty && globals.hasReferences(layouts);
    final heap = HeapPlan(program, selected, layouts, frames);
    final members = MemberCalls(program, selected, heap.heap.invalid);
    final relocations = <Relocation>[];
    final nativeSymbols = <String, int>{};
    final nativeCalls = <(int, Fixup, int)>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
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
      } else if (declaration == globals.address) {
        // The module storage address is emitted below as a leaf primitive.
      } else if (function is! IrFunction) {
        throw ArgumentError('Definition has no body: ${declaration.name}');
      } else {
        functions[declaration] = ScalarFunction(
          function,
          _createFunction(),
          layouts,
          heap,
          traces,
          casts,
          members,
          arithmetic,
          globals,
        );
      }
      final export = exports[declaration];
      if (export != null && !_matches(declaration, export.signature)) {
        throw ArgumentError('Native signature mismatch: ${declaration.name}');
      }
    }
    final generated = [...arithmetic.functions, ...globals.functions];
    Iterable<IrFunction> supportFunctions() => [
      ...arithmetic.functions,
      ...globals.functions,
      ...casts.functions,
      ...layouts.relations.functions,
      ...layouts.types.functions,
    ];
    var pending = [
      for (final function in supportFunctions())
        if (!functions.containsKey(function.target)) function,
    ];
    while (pending.isNotEmpty) {
      generated.addAll(pending);
      heap.include(pending, layouts);
      for (final function in pending) {
        selected.add(function.target);
        functions[function.target] = ScalarFunction(
          function,
          _createFunction(),
          layouts,
          heap,
          traces,
          casts,
          members,
          arithmetic,
          globals,
        );
      }
      pending = [
        for (final function in supportFunctions())
          if (!functions.containsKey(function.target)) function,
      ];
    }
    heap.retain({
      for (final function in functions.values)
        for (final call in function.selection.calls.values) ?call.target,
    });
    final capture = functions.values.any(
      (function) => function.selection.calls.values.any(
        (call) => call.target == traces.capture,
      ),
    );
    final exceptions = functions.values.any(
      (function) => function.selection.body.ends.values.any(
        (end) => end is Throw || end is Invoke,
      ),
    );
    final traceFunctions = capture
        ? traces.functions(heap.heap.invalid)
        : <IrFunction>[];
    heap.include(traceFunctions, layouts);
    final managed = persistent || !heap.isEmpty || exceptions;
    final primitives = managed ? heap.primitives : <FunctionTarget>{};
    if (managed || generated.isNotEmpty) {
      final support = [
        ...generated,
        if (managed) ...heap.functions,
        if (managed) frames.function,
        ...traceFunctions,
      ];
      IrProgram(
        [
          if (casts.functions.isNotEmpty) ...casts.classes,
          if (!globals.isEmpty) globals.declaration,
          ...arithmetic.classes,
          ...layouts.types.classes,
          ...layouts.relations.classes,
          if (capture) traces.declaration,
        ],
        support,
        externals: [
          for (final target in [
            heap.heap.map,
            heap.heap.unmap,
            heap.heap.invalid,
          ])
            IrExternal(target),
          if (!globals.isEmpty) IrExternal(globals.address),
        ],
      );
      selected.addAll([
        ...support.map((f) => f.target),
        ...primitives,
        if (capture) traces.capture,
      ]);
      for (final function in support) {
        if (functions.containsKey(function.target)) continue;
        functions[function.target] = ScalarFunction(
          function,
          _createFunction(),
          layouts,
          heap,
          traces,
          casts,
          members,
          arithmetic,
          globals,
        );
      }
    }
    final cleanup = FunctionTarget(
      Uri.parse('dartc:globals'),
      'release',
      .voidType,
      [],
    );
    if (persistent && entryPoint == null) selected.add(cleanup);
    final indices = {
      for (final (i, declaration) in selected.indexed) declaration: i,
    };
    final hasRoots = managed || functions.values.any((f) => f.hasRoots);
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
    final globalAddresses = <(int, Fixup)>[],
        contextAddresses = <(int, Fixup)>[];
    final rootAddresses = <(int, Fixup)>[],
        errorAddresses = <(int, Fixup)>[],
        uncaughtAddresses = <(int, Fixup)>[];
    void call(Fixup fixup, FunctionTarget callee) {
      final index = indices[callee];
      if (index == null) {
        throw ArgumentError('Missing call definition: ${callee.name}');
      }
      relocations.add(
        .instruction(0, code.length + fixup.offset, fixup.encoding, index),
      );
    }

    HeapEntry<R>? entry(FunctionEmitter<R> emitter) => !managed
        ? null
        : HeapEntry(
            emitter,
            heap.heap,
            (fixup) => rootAddresses.add((code.length, fixup)),
            (fixup) => errorAddresses.add((code.length, fixup)),
            (fixup) => uncaughtAddresses.add((code.length, fixup)),
            call,
            context: persistent
                ? (fixup) => contextAddresses.add((code.length, fixup))
                : null,
            globals: persistent
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
      final frame = emitter.convention.frameLayout(
        localBytes: 0,
        localAlignment: 8,
        savedRegisters: [],
        outgoingStackBytes: destination.stackBytes,
      );
      emitter.prologue(frame);
      final argument =
          (destination.parameters.single as RegisterArgument<R>).register;
      emitter.address(
        argument,
        (fixup) => contextAddresses.add((code.length, fixup)),
      );
      call(emitter.call(), heap.heap.release);
      emitter.epilogue(frame);
      return emitter.finish();
    }

    for (final declaration in selected) {
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
            )
          : binding != null
          ? NativeAdapter(emitter).generate(
              binding.signature,
              (fixup, position, frame) {
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
      final context = entry(emitter);
      final frame = context?.frame(0);
      final bytes = emitter.start(() {
        if (context != null) context.enter(frame!);
        final fixup = emitter.call();
        call(fixup, function);
        safepoint(emitter.position, StackRoots(0, 0, []));
        if (context != null) context.leave(frame!, null, release: true);
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
    symbols.addAll(constants.symbols);
    final sections = [
      Section.code(code.takeBytes()),
      if (constants.symbols.isNotEmpty) constants.finish(),
    ];
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
        Relocation.address(section, ObjectLayout.descriptorOffset, descriptor!),
        Relocation.address(section, ObjectLayout.typeOffset, globalType!),
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
          HeapFunctions.contextBytes,
          kind: .data,
          binding: .local,
        ),
      );
      sections.add(Section.zeroFill(HeapFunctions.contextBytes, alignment: 8));
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
      declaration.typeParameters.isEmpty &&
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
