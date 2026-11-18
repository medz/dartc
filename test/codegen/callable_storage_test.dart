import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart' show Arm64CodeGenerator;
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/callable_implementations.dart';
import 'package:dartc/src/codegen/callable_lowering.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/indirect_invocation.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/storage_access.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/src/codegen/value_operations.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final native = NativeLayout(const Target(.linux, .arm64));

  test(
    'stored function identity and recursive metadata need no code entries',
    () {
      final target = FunctionTarget(null, 'uncalled', .integer, [.integer]);
      final value = FunctionConstant(target);
      final closures = ClosureStorage([]);
      final layout = ProgramLayout(
        [],
        closureStorage: closures,
        nativeLayout: native,
        typeRuntime: heapRuntime.types,
      );
      final data = ConstantData(layout, 0);
      final symbol = data.addressOf(value);
      final shape = closures.constants[value.structuralKey]!;
      expect(data.addressOf(value), symbol);
      expect(data.callableTable(target), isNull);
      expect(closures.implementations.functions, isEmpty);
      expect(closures.functions, isEmpty);
      expect(closures.constants.length, greaterThan(1));
      final bytes = ByteData.sublistView(data.finish().bytes);
      final offset =
          data.symbols[symbol].offset +
          layout.storageOf(shape.type).offsetOf(closures.entryTable);
      expect(bytes.getInt64(offset, Endian.little), 0);
      expect(
        data.relocations.where((relocation) => relocation.offset == offset),
        isEmpty,
      );
      expect(
        data.relocations.every(
          (relocation) => relocation.symbol < data.symbols.length,
        ),
        isTrue,
      );
    },
  );

  test(
    'a callable allocation receives its supplied runtime descriptor once',
    () {
      final closures = ClosureStorage([]);
      final storage = closures.instantiated;
      final root = FunctionTarget(null, 'apply', .function, [
        .function,
        TypeMetadata.list.nullable,
        TypeMetadata.type,
      ]);
      final entry = Block(root.parameterTypes);
      final value = entry.emit(
        Construct.callable(
          storage,
          entry.parameters.take(2),
          ValueType.function,
          entry.parameters.last,
        ),
      );
      entry.finish(Return(value));
      final body = IrFunction(root, [entry]);
      final graph = IrProgram(
        [
          for (final entry in TypeMetadata.fields.entries)
            IrClass(entry.key, entry.value),
          ...closures.classes,
        ],
        [body, ...closures.functions],
      );
      final selected = FunctionRepresentation(
        body,
        ProgramLayout(
          graph.classes,
          closureStorage: closures,
          nativeLayout: native,
        ),
        CheckedCasts(),
        MemberCalls(graph, {root}),
        HeapPlan(),
      );
      expect(selected.inputsOf(value), orderedEquals(entry.parameters));
    },
  );

  test(
    'missing optional defaults are rejected even for identity-only storage',
    () {
      final target = FunctionTarget(null, 'optional', .integer, [
        .integer,
      ], optionalPositional: 1);
      expect(
        () => ClosureStorage([]).ensureConstant(FunctionConstant(target)),
        throwsStateError,
      );
      final body = IrFunction(
        target,
        [
          Block(target.parameterTypes)
            ..finish(const Return(Constant.integer(0))),
        ],
        defaults: {0: const Constant.integer(9)},
      );
      expect(
        ClosureStorage(
          [],
          definitions: [body],
        ).ensureConstant(FunctionConstant(target)).defaults[0],
        const Constant.integer(9),
      );
    },
  );

  test(
    'actual typed entries become one indirect call and code relocations',
    () {
      final targets = [
        for (var i = 0; i < 2; i++)
          FunctionTarget(null, 'source$i', .integer, [.integer]),
      ];
      final bodies = [
        for (final (i, target) in targets.indexed)
          () {
            final entry = Block(target.parameterTypes);
            entry.finish(
              Return(
                entry.emit(
                  IntBinary(
                    .add,
                    entry.parameters.single,
                    Constant.integer(i + 1),
                  ),
                ),
              ),
            );
            return IrFunction(target, [entry]);
          }(),
      ];
      final root = FunctionTarget(null, 'invoke', .integer, [.boolean]);
      final entry = Block(root.parameterTypes),
          yes = Block(),
          no = Block(),
          join = Block([targets.first.signature]);
      entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
      yes.finish(Jump(join, [FunctionConstant(targets.first)]));
      no.finish(Jump(join, [FunctionConstant(targets.last)]));
      final call = join.emit(
        FunctionCall(join.parameters.single, [const Constant.integer(7)]),
      );
      join.finish(Return(call));
      final source = IrProgram([], [
        ...bodies,
        IrFunction(root, [entry, yes, no, join]),
      ]);
      final implementations = CallableImplementations();
      final firstFacts = ProgramFlow(
        source,
        const [],
        openEntries: [root],
      ).facts;
      final program = CallableLowering(implementations).run(firstFacts);
      final facts = ProgramFlow(program, const [], openEntries: [root]).facts;
      final rewritten = program.implementationOf(root)! as IrFunction;
      final bound = rewritten.blocks
          .expand((block) => block.instructions)
          .whereType<FunctionCall>()
          .single;
      expect(
        facts.targetsOf(bound),
        bound.entryBinding!.entries.values.toSet(),
      );
      expect(IrInterpreter(program, {}).run(rewritten, [true]), 8);
      expect(IrInterpreter(program, {}).run(rewritten, [false]), 9);
      final closures = ClosureStorage(
        program.functions,
        callableImplementations: implementations,
      );
      final layout = ProgramLayout(
        closures.classes,
        closureStorage: closures,
        nativeLayout: native,
      );
      final represented = FunctionRepresentation(
        rewritten,
        layout,
        CheckedCasts(),
        MemberCalls(program, facts.definitions, callTypes: facts),
        HeapPlan(),
      );
      final operations = represented.instructions.values
          .expand((values) => values)
          .toList();
      expect(operations.whereType<IndirectInvocation>(), hasLength(1));
      expect(operations.whereType<StorageRead>().map((read) => read.field), [
        FunctionStorage.entries,
      ]);
      expect(represented.blocks.length, rewritten.blocks.length);
      final symbols = {
        for (final (i, body) in implementations.functions.indexed)
          body.target: i,
      };
      final data = ConstantData(
        layout,
        symbols.length,
        functionSymbols: symbols,
      );
      for (final target in targets) {
        data.addressOf(FunctionConstant(target));
        expect(data.callableTable(target), isNotNull);
      }
      expect(
        data.relocations
            .where((relocation) => relocation.symbol < symbols.length)
            .map((relocation) => relocation.symbol)
            .toSet(),
        symbols.values.toSet(),
      );
    },
  );

  test(
    'identity extraction has a fixed graph independent of stored targets',
    () {
      for (final count in [1, 64]) {
        final targets = [
          for (var i = 0; i < count; i++)
            FunctionTarget(null, 'function$i', .integer, []),
        ];
        final closures = ClosureStorage(
          [],
          storedFunctions: targets.map(FunctionConstant.new),
        );
        final layout = ProgramLayout(
          closures.classes,
          closureStorage: closures,
          nativeLayout: native,
          typeRuntime: heapRuntime.types,
        );
        final target = FunctionTarget(null, 'hash', .integer, [
          targets.first.signature,
        ]);
        final entry = Block(target.parameterTypes);
        final graph = SelectedFunction(target, layout, entry);
        graph.blocks.add(entry);
        graph.instructions[entry] = [];
        final result = ValueOperations(
          graph,
          layout,
          heapRuntime.typeCheckFailure!,
        ).hashFunction(entry.parameters.single, entry);
        graph.ends[result] = Return(result.parameters.single);
        expect(graph.blocks, hasLength(3));
        expect(graph.ends.values.whereType<Branch>(), isEmpty);
        final reads = graph.instructions.values
            .expand((values) => values)
            .whereType<StorageRead>();
        expect(reads.map((read) => read.field).toSet(), {
          closures.identity,
          closures.identityAnchor,
          closures.identityArguments,
        });
      }
    },
  );
  test('public preparation reconstructs entries from the rewritten graph', () {
    final sources = [
      for (var i = 0; i < 2; i++)
        FunctionTarget(null, 'source$i', .integer, [.integer]),
    ];
    final bodies = [
      for (final (i, target) in sources.indexed)
        () {
          final entry = Block(target.parameterTypes);
          entry.finish(
            Return(
              entry.emit(
                IntBinary(
                  .add,
                  entry.parameters.single,
                  Constant.integer(i + 1),
                ),
              ),
            ),
          );
          return IrFunction(target, [entry]);
        }(),
    ];
    final root = FunctionTarget(null, 'choose', .integer, [.boolean]);
    final entry = Block(root.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block([sources.first.signature]);
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    yes.finish(Jump(join, [FunctionConstant(sources.first)]));
    no.finish(Jump(join, [FunctionConstant(sources.last)]));
    join.finish(
      Return(
        join.emit(
          FunctionCall(join.parameters.single, const [Constant.integer(7)]),
        ),
      ),
    );
    final program = IrProgram([], [
      ...bodies,
      IrFunction(root, [entry, yes, no, join]),
    ]);
    const platform = Target(.linux, .arm64);
    final first = Compiler(platform).prepare(program, roots: [root]);
    final second = Compiler(platform).prepare(first.program, roots: [root]);
    for (final prepared in [first, second]) {
      final body = prepared.program.implementationOf(root) as IrFunction;
      expect(IrInterpreter(prepared.program, {}).run(body, [true]), 8);
      expect(IrInterpreter(prepared.program, {}).run(body, [false]), 9);
      expect(
        Arm64CodeGenerator(platform).generate(prepared).sections,
        isNotEmpty,
      );
    }
  });
}
