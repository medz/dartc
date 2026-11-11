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
import 'program_selection.dart';
import 'scalar_function.dart';
import 'native_adapter.dart';
import 'native_bindings.dart';
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
import 'instance_storage.dart';
import 'closure_storage.dart';
import 'string_storage.dart';

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
    for (final declaration in selected) {
      for (final callee
          in program.implementationOf(declaration)?.callees ??
              const <FunctionTarget>[]) {
        if (!selected.contains(callee.implementation)) {
          throw ArgumentError('Missing call definition: ${callee.name}');
        }
      }
    }
    final bindings = NativeBindings(program, imports, exports);
    program = bindings.program;
    imports = bindings.imports;
    exports = bindings.exports;
    selected.addAll(bindings.definitions);
    final sourceProgram = program;
    final sourceDefinitions = {...selected};
    late final ProgramSelection resolved;
    while (true) {
      program = sourceProgram;
      selected
        ..clear()
        ..addAll(sourceDefinitions);
      final frames = FrameLookup();
      final traces = StackTraces(frames);
      final casts = CheckedCasts();
      IrCallable? constructor(ValueType type, [String name = 'new']) {
        final target = program.classes
            .where((c) => c.type == type)
            .firstOrNull
            ?.constructors[name];
        return target == null ? null : program.implementationOf(target);
      }

      final lateErrorType = program.classes
          .where(
            (declaration) =>
                declaration.type.library == Uri.parse('dart:_internal') &&
                declaration.type.name == 'LateError',
          )
          .firstOrNull
          ?.type;
      final bodies = sourceDefinitions
          .map(sourceProgram.implementationOf)
          .whereType<IrFunction>();
      final indexErrorType = program.classes
          .where(
            (c) =>
                c.type.library == Uri.parse('dart:core') &&
                c.type.name == 'IndexError',
          )
          .firstOrNull
          ?.type;
      final strings = StringStorage(
        indexError: indexErrorType == null
            ? null
            : constructor(indexErrorType, 'withLength'),
      );
      final arithmetic = NumericOperations(
        argumentError: constructor(.argumentError),
        unsupportedError: constructor(.unsupportedError),
      );
      final globals = GlobalStorage(
        bodies,
        lateError: lateErrorType == null ? null : constructor(lateErrorType),
      );
      final instances = InstanceStorage(
        bodies,
        lateError: lateErrorType == null ? null : constructor(lateErrorType),
      );
      for (final body in bodies) {
        for (final block in body.blocks) {
          final operations = switch (block.end) {
            Invoke(:final operation) => block.instructions.followedBy([
              operation,
            ]),
            _ => block.instructions,
          };
          for (final operation in operations) {
            arithmetic.callFor(operation);
            strings.callFor(operation);
          }
        }
      }
      final helpers = [
        ...arithmetic.functions,
        ...strings.functions,
        ...globals.functions,
        ...instances.functions,
      ];
      if (helpers.isNotEmpty) {
        final expanded = IrProgram(
          [
            for (final declaration in sourceProgram.classes)
              if (declaration.type == ValueType.string &&
                  strings.functions.isNotEmpty)
                IrClass(
                  declaration.type,
                  strings.declaration.fields,
                  members: declaration.members.values,
                  implementations: declaration.implementations.values,
                  constructors: declaration.constructors.values,
                  unsupportedForwarders: declaration.unsupportedForwarders,
                )
              else
                declaration,
            if (strings.functions.isNotEmpty &&
                !sourceProgram.classes.any((c) => c.type == ValueType.string))
              strings.declaration,
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
        if (discovered.isNotEmpty) {
          sourceDefinitions.addAll(discovered);
          continue;
        }
        program = expanded;
        selected
          ..clear()
          ..addAll(required);
      }
      final members = MemberCalls(program, selected);
      final closures = ClosureStorage(
        selected.map(program.implementationOf).whereType<IrCallable>(),
        boundMethods: members.tearOffTargets,
        lateFailure: instances.failure?.target,
      );
      final layouts = ProgramLayout(
        [
          ...casts.classes,
          ...arithmetic.classes,
          ...program.classes,
          ...closures.classes,
          traces.declaration,
        ],
        instanceStorage: instances,
        closureStorage: closures,
        stringStorage: strings,
        referencedClasses: selected.expand(
          (target) =>
              program.implementationOf(target)?.referencedClasses ?? const [],
        ),
      );
      final persistent = !globals.isEmpty && globals.hasReferences(layouts);
      final heap = HeapPlan(frames);
      final selection = ProgramSelection(
        layouts,
        heap,
        frames,
        traces,
        casts,
        members,
        arithmetic,
        globals,
        instances,
      );
      for (final declaration in selected) {
        final function = program.implementationOf(declaration);
        final binding = imports[declaration];
        if (binding != null || declaration == globals.address) continue;
        if (function is! IrFunction) {
          throw ArgumentError('Definition has no body: ${declaration.name}');
        } else {
          selection.include(function);
        }
      }
      final missing = selection.close(persistent: persistent);
      for (final target in missing) {
        if (sourceProgram.implementationOf(target) == null) {
          throw ArgumentError('Missing support dependency: ${target.name}');
        }
      }
      if (missing.isNotEmpty) {
        sourceDefinitions.addAll(sourceProgram.reachableFrom(missing));
        continue;
      }
      resolved = selection;
      break;
    }
    final selection = resolved;
    final layouts = selection.layouts, heap = selection.heap;
    final globals = selection.globals, traces = selection.traces;
    final persistent = !globals.isEmpty && globals.hasReferences(layouts);
    final relocations = <Relocation>[];
    final nativeSymbols = <String, int>{};
    final nativeCalls = <(int, Fixup, int)>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    final functions = {
      for (final body in selection.functions.values)
        body.function.target: ScalarFunction(body, _createFunction(), traces),
    };
    final capture = selection.capture, managed = selection.managed;
    final primitives = selection.primitives;
    selected.addAll([
      ...functions.keys,
      ...primitives,
      if (capture) traces.capture,
    ]);
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

  bool _needsEntry(NativeSignature signature) => [
    signature.result,
    ...signature.parameters,
  ].any((t) => t.isSinglePrecision || (t.integerLayout?.bytes ?? 8) < 8);
}
