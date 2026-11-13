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
import 'heap_runtime.dart';
import 'stack_traces.dart';
import 'checked_casts.dart';
import 'member_calls.dart';
import 'numeric_operations.dart';
import 'global_storage.dart';
import 'instance_storage.dart';
import 'closure_storage.dart';
import 'string_storage.dart';
import 'list_storage.dart';
import 'record_storage.dart';
import 'async_functions.dart';

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
    Map<NativeReference, String> nativeSymbols = const {},
    ({FunctionTarget function, String symbol})? entryPoint,
    HeapRuntime? runtime,
  }) {
    final selected = definitions.toSet();
    if (selected.isEmpty ||
        !selected.containsAll([...exports.keys, ...imports.keys]) ||
        exports.keys.any(imports.containsKey)) {
      throw ArgumentError(
        'Expected distinct exports and imports in definitions.',
      );
    }
    for (final missing
        in program.reachableFrom(selected).difference(selected)) {
      throw ArgumentError(
        'Missing ${missing.kind.isVirtual ? 'member' : 'call'} definition: ${missing.name}',
      );
    }
    if (runtime != null && !identical(program, runtime.program)) {
      final classes = {for (final c in program.classes) c.type: c};
      for (final declaration in runtime.program.classes) {
        final existing = classes[declaration.type];
        if (existing != null &&
            (existing.fields.isNotEmpty &&
                    (existing.fields.length != declaration.fields.length ||
                        existing.fields.indexed.any(
                          (entry) => entry.$2 != declaration.fields[entry.$1],
                        )) ||
                existing.members.entries.any(
                  (entry) => declaration.members[entry.key] != entry.value,
                ) ||
                existing.constructors.entries.any(
                  (entry) => declaration.constructors[entry.key] != entry.value,
                ))) {
          throw ArgumentError(
            'Conflicting runtime class: ${declaration.type.name}',
          );
        }
        classes[declaration.type] = declaration;
      }
      final functions = {
        for (final function in program.functions) function.target: function,
      };
      for (final function in runtime.program.functions) {
        final existing = functions[function.target];
        if (existing != null && !identical(existing, function)) {
          throw ArgumentError(
            'Conflicting runtime definition: ${function.target.name}',
          );
        }
        functions[function.target] = function;
      }
      program = IrProgram(
        classes.values,
        functions.values,
        globals: {...program.globals, ...runtime.program.globals},
        externals: {
          for (final external in [
            ...runtime.program.externals,
            ...program.externals,
          ])
            if (!functions.containsKey(external.target))
              external.target: external,
        }.values,
      );
    }
    final bindings = NativeBindings(program, imports, exports);
    program = bindings.program;
    imports = bindings.imports;
    exports = bindings.exports;
    selected.addAll(bindings.definitions);
    selected.addAll(program.reachableFrom(selected));
    final sourceProgram = program;
    final sourceDefinitions = {...selected};
    late final ProgramSelection resolved;
    while (true) {
      program = sourceProgram;
      selected
        ..clear()
        ..addAll(sourceDefinitions);
      final heap = HeapPlan(runtime: runtime);
      final traces = StackTraces(runtime);
      final casts = CheckedCasts();
      IrCallable? constructor(ValueType? type, [String name = 'new']) {
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
      final strings = StringStorage(
        source: program.classes
            .where((c) => c.type == ValueType.string)
            .firstOrNull,
      );
      final arithmetic = NumericOperations(
        floatingRemainder: runtime?.floatingRemainder,
        floatingModulo: runtime?.floatingModulo,
        argumentError: constructor(.argumentError),
        unsupportedError: constructor(.unsupportedError),
      );
      final constantLists = bodies.any(
        (body) => body.sequenceConstants.any(
          (value) => (value.type as ClassType).declaration == CoreTypes.list,
        ),
      );
      final lists = ListStorage(program.classes);
      // Codegen materializes these instances without source constructor calls.
      final instantiatedTypes = [
        ...TypeMetadata.fields.keys,
        if (constantLists) lists.type,
      ];
      final records = RecordStorage(
        program.classes,
        bodies.expand((body) => body.recordTypes),
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
          }
        }
      }
      final helpers = [
        ...arithmetic.functions,
        ...globals.functions,
        ...instances.functions,
      ];
      if (helpers.isNotEmpty || constantLists) {
        final expanded = IrProgram(
          [
            for (final declaration in sourceProgram.classes)
              if (declaration.type == ValueType.string)
                strings.declaration
              else
                declaration,
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
        ], instantiatedTypes: instantiatedTypes);
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
      final members = MemberCalls(
        program,
        selected,
        records: records,
        instantiatedTypes: instantiatedTypes,
      );
      final asynchronous = AsyncFunctions(
        selected.map(program.implementationOf).whereType<IrFunction>(),
      );
      final closures = ClosureStorage(
        [
          ...selected.map(program.implementationOf).whereType<IrCallable>(),
          ...asynchronous.entries,
        ],
        boundMethods: [
          ...members.tearOffTargets,
          ...asynchronous.entries.map((entry) => entry.target),
        ],
        lateFailure: instances.failure?.target,
      );
      final layouts = ProgramLayout(
        [
          ...casts.classes,
          ...arithmetic.classes,
          ...program.classes,
          ...closures.classes,
          ...asynchronous.classes,
        ],
        nativeLayout: NativeLayout(target),
        functions: program.functions,
        instanceStorage: instances,
        closureStorage: closures,
        stringStorage: strings,
        listStorage: lists,
        recordStorage: records,
        typeRuntime: runtime?.types,
        referencedClasses: selected.expand(
          (target) =>
              program.implementationOf(target)?.referencedClasses ?? const [],
        ),
      );
      final persistent = !globals.isEmpty && globals.hasReferences(layouts);
      final selection = ProgramSelection(
        layouts,
        heap,
        traces,
        casts,
        members,
        arithmetic,
        globals,
        instances,
        asyncFunctions: asynchronous,
      );
      for (final declaration in selected) {
        final function = program.implementationOf(declaration);
        final binding = imports[declaration];
        if (binding != null ||
            declaration == globals.address ||
            heap.primitives.contains(declaration)) {
          continue;
        }
        if (declaration == runtime?.types?.supertypes) {
          selection.include(layouts.relations.supertypes);
        } else if (function is! IrFunction) {
          throw ArgumentError(
            'Definition has no body: ${declaration.library}::'
            '${declaration.owner == null ? '' : '${declaration.owner!.dartName}.'}'
            '${declaration.name}',
          );
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
        sourceDefinitions.addAll(
          sourceProgram.reachableFrom([
            ...sourceDefinitions,
            ...missing,
          ], instantiatedTypes: instantiatedTypes),
        );
        continue;
      }
      resolved = selection;
      break;
    }
    if (resolved.managed) {
      for (final function in runtime!.nonAllocating) {
        if (resolved.functions.containsKey(function)) {
          resolved.checkNonAllocating(function);
        }
      }
    }
    final selection = resolved;
    final layouts = selection.layouts, heap = selection.heap;
    final globals = selection.globals, traces = selection.traces;
    final persistent = !globals.isEmpty && globals.hasReferences(layouts);
    final relocations = <Relocation>[];
    final symbolNames = <String, int>{};
    final nativeCalls = <(int, Fixup, int)>[];
    final nativeAddresses = <(int, Fixup, int)>[];
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    final functions = {
      for (final body in selection.functions.values)
        body.target: ScalarFunction(body, _createFunction()),
    };
    final capture = selection.capture, managed = selection.managed;
    final primitives = selection.primitives;
    selected.addAll([
      ...functions.keys,
      ...primitives,
      ...layouts.nativeCalls.signatures.keys,
      if (capture) traces.capture,
    ]);
    final cleanup = FunctionTarget(null, 'release', .voidType, []);
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
            heap.release,
            selected.contains(heap.eventAccess) ? heap.runEvents : null,
            (fixup) => rootAddresses.add((code.length, fixup)),
            (fixup) => errorAddresses.add((code.length, fixup)),
            (fixup) => uncaughtAddresses.add((code.length, fixup)),
            call,
            (position) => safepoint(position, StackRoots(0, 0, [])),
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
                final symbol = symbolNames.putIfAbsent(
                  '.dartc.clock',
                  () => symbolNames.length,
                );
                nativeCalls.add((code.length, fixup, symbol));
              },
            )
          : binding != null
          ? NativeAdapter(emitter).generate(
              binding.signature,
              (fixup, position, frame) {
                final symbol = symbolNames.putIfAbsent(
                  target.nativeSymbol(binding.symbol),
                  () => symbolNames.length,
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
                if (name == null || name.isEmpty || name.contains('\u0000')) {
                  throw ArgumentError(
                    'Unbound native address: ${reference.assetId}::${reference.symbol}',
                  );
                }
                final symbol = symbolNames.putIfAbsent(
                  target.nativeSymbol(name),
                  () => symbolNames.length,
                );
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
          (body.bodyKind != .synchronous && body.bodyKind != .asynchronous) ||
          function.kind != .function ||
          function.parameterTypes.isNotEmpty ||
          function.typeParameters.isNotEmpty) {
        throw UnsupportedError(
          'Process entry requires a parameterless function.',
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
      [signature.result, ...signature.parameters].any(
        (t) =>
            t is NativeCompoundType ||
            t.isSinglePrecision ||
            (t.integerLayout?.bytes ?? 8) < 8,
      );
}
