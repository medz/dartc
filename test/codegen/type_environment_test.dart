import 'package:dartc/codegen.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/program_preparation.dart';
import 'package:dartc/src/codegen/type_environment.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:type-environment');
  TypeParameterType parameter(String name) =>
      TypeParameterType(name)..initializeBound(.object.nullable);

  test(
    'runtime type decisions separate value proofs from nominal arguments',
    () {
      final t = parameter('T');
      final holder = ClassType(uri, 'Holder', typeParameters: [t]);
      final proof = InstantiatedPromotionType(
        ValueType.object,
        ValueType.integer,
      );
      final source = holder.instantiate([proof]);
      final layout = ProgramLayout([
        IrClass(holder, []),
      ], nativeLayout: NativeLayout(const Target(.linux, .arm64)));
      expect(
        layout.typeTest(proof, ValueType.integer),
        TypeTestKind.constantTrue,
      );
      expect(
        layout.typeTest(source, holder.instantiate([ValueType.integer])),
        isNot(TypeTestKind.constantTrue),
      );
      expect(
        layout.types.constant(source).structuralKey,
        layout.types
            .constant(holder.instantiate([ValueType.object]))
            .structuralKey,
      );
      final record = RecordType([proof]);
      expect(
        layout.typeTest(record, RecordType([ValueType.integer])),
        TypeTestKind.constantTrue,
      );
    },
  );

  test(
    'a closure consumes an explicit lexical metadata input only when used',
    () {
      final t = parameter('T'), unused = parameter('Unused');
      final outer = FunctionTarget(
        uri,
        'outer',
        .integer,
        [],
        typeParameters: [t, unused],
      );
      final source = FunctionTarget(
        uri,
        'capturedType',
        .typeType,
        [],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 1,
      );
      final entry = Block(source.parameterTypes);
      final reified = entry.emit(ReifyType(t));
      entry.finish(Return(reified));
      final body = IrFunction(source, [entry]);
      final program = IrProgram(
        [
          for (final type in TypeMetadata.fields.entries)
            IrClass(type.key, type.value),
        ],
        [
          body,
          IrFunction(outer, [
            Block()..finish(const Return(Constant.integer(0))),
          ]),
        ],
      );
      final environment = TypeEnvironment([source]);
      final layout = ProgramLayout(
        program.classes,
        typeEnvironment: environment,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final represented = FunctionRepresentation(
        body,
        layout,
        CheckedCasts(),
        MemberCalls(program, {source}),
        HeapPlan(),
      );
      expect(environment.lexicalParametersOf(source), [t]);
      expect(represented.entryParameters, hasLength(2));
      expect(represented.inputsOf(reified), [represented.entryParameters.last]);
      expect(represented.callees, isEmpty);
      expect(layout.entryTypes(source), [source.signature, TypeMetadata.type]);
    },
  );

  for (final architecture in [Architecture.arm64, Architecture.x64]) {
    final platform = Target(.linux, architecture);
    // These representation tests retain calls deliberately. The public compiler
    // also optimizes them; its short paths are covered by prepared_program_test.
    PreparedProgram prepare(
      IrProgram program, {
      required Iterable<FunctionTarget> roots,
    }) {
      final boundaries = NativeBoundaries(program, roots: roots);
      final preparation = ProgramPreparation(
        platform,
        boundaries.program,
        boundaries: boundaries,
      );
      return preparation.prepare(
        CallTypeFlow(
          preparation.program,
          preparation.roots,
          instantiatedTypes: preparation.instantiatedTypes,
        ).facts,
      );
    }

    void emit(PreparedProgram prepared) {
      final generator = architecture == .arm64
          ? Arm64CodeGenerator(platform)
          : X64CodeGenerator(platform);
      expect(generator.generate(prepared).sections, isNotEmpty);
    }

    test(
      '$architecture reification does not retain erased promotion metadata',
      () {
        final t = parameter('T'), u = parameter('U');
        final generic = FunctionTarget(
          uri,
          'lexicalType',
          .typeType,
          [],
          typeParameters: [t, u],
        );
        final body = Block();
        body.finish(
          Return(body.emit(ReifyType(PromotedTypeParameterType(t, u)))),
        );
        final root = FunctionTarget(uri, 'root', .typeType, []);
        final entry = Block();
        entry.finish(
          Return(
            entry.emit(
              DirectCall(
                generic,
                [],
                typeArguments: [ValueType.object, ValueType.integer],
              ),
            ),
          ),
        );
        final prepared = prepare(
          IrProgram([], [
            IrFunction(root, [entry]),
            IrFunction(generic, [body]),
          ]),
          roots: [root],
        );
        expect(
          prepared.selection.layouts.typeEnvironment.parametersOf(generic),
          [0],
        );
        emit(prepared);
      },
    );

    test('$architecture recursive permutations close both hidden inputs', () {
      final a = parameter('A'), b = parameter('B');
      final recursive = FunctionTarget(
        uri,
        'recursiveType',
        .typeType,
        [.integer],
        typeParameters: [a, b],
      );
      final entry = Block(recursive.parameterTypes),
          done = Block(),
          again = Block();
      final depth = entry.parameters.single;
      entry.finish(
        Branch(
          entry.emit(IntBinary(.lessOrEqual, depth, const Constant.integer(0))),
          Jump(done),
          Jump(again),
        ),
      );
      final reified = done.emit(ReifyType(b));
      done.finish(Return(reified));
      final call = again.emit(
        DirectCall(
          recursive,
          [again.emit(IntBinary(.subtract, depth, const Constant.integer(1)))],
          typeArguments: [b, a],
        ),
      );
      again.finish(Return(call));
      final root = FunctionTarget(uri, 'root', .typeType, [.integer]);
      final start = Block(root.parameterTypes);
      start.finish(
        Return(
          start.emit(
            DirectCall(
              recursive,
              start.parameters,
              typeArguments: [.integer, .floating],
            ),
          ),
        ),
      );
      final prepared = prepare(
        IrProgram([], [
          IrFunction(root, [start]),
          IrFunction(recursive, [entry, done, again]),
        ]),
        roots: [root],
      );
      final body = prepared.selection.functions[recursive]!;
      expect(
        prepared.selection.layouts.typeEnvironment.parametersOf(recursive),
        [0, 1],
      );
      expect(body.entryParameters, hasLength(3));
      expect(body.inputsOf(reified), [body.entryParameters[2]]);
      expect(body.inputsOf(call).skip(1), [
        body.entryParameters[2],
        body.entryParameters[1],
      ]);
      emit(prepared);
    });

    test('$architecture unused generic calls need no type construction', () {
      final t = parameter('T'), u = parameter('U');
      final leaf = FunctionTarget(
        uri,
        'leaf',
        .integer,
        [.integer],
        typeParameters: [t],
      );
      final relay = FunctionTarget(
        uri,
        'relay',
        .integer,
        [.integer],
        typeParameters: [u],
      );
      final root = FunctionTarget(uri, 'root', .integer, [.integer]);
      // Build the value in its owning entry; no optimizer or inlining is used.
      final actualLeaf = Block(leaf.parameterTypes);
      actualLeaf.finish(Return(actualLeaf.parameters.single));
      final relayBody = Block(relay.parameterTypes);
      final forwarded = relayBody.emit(
        DirectCall(
          leaf,
          relayBody.parameters,
          typeArguments: [CoreTypes.listOf(u)],
        ),
      );
      relayBody.finish(Return(forwarded));
      final entry = Block(root.parameterTypes);
      final called = entry.emit(
        DirectCall(relay, entry.parameters, typeArguments: [.integer]),
      );
      entry.finish(Return(called));
      final prepared = prepare(
        IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(relay, [relayBody]),
          IrFunction(leaf, [actualLeaf]),
        ]),
        roots: [root],
      );
      final selection = prepared.selection;
      expect(selection.layouts.entryTypes(leaf), [ValueType.integer]);
      expect(selection.layouts.entryTypes(relay), [ValueType.integer]);
      expect(selection.functions[relay]!.inputsOf(forwarded).length, 1);
      expect(selection.functions[root]!.inputsOf(called).length, 1);
      expect(prepared.definitions, {root, relay, leaf});
      expect(leaf.typeParameters, [t]);
      expect(relay.typeParameters, [u]);
      emit(prepared);
    });

    test('$architecture sparse demands propagate through reordered calls', () {
      final a = parameter('A'), b = parameter('B');
      final x = parameter('X'), y = parameter('Y');
      final leaf = FunctionTarget(
        uri,
        'typeOfSecond',
        .typeType,
        [],
        typeParameters: [a, b],
      );
      final relay = FunctionTarget(
        uri,
        'reorder',
        .typeType,
        [],
        typeParameters: [x, y],
      );
      final root = FunctionTarget(uri, 'root', .typeType, []);
      final leafBody = Block();
      final reified = leafBody.emit(ReifyType(b));
      leafBody.finish(Return(reified));
      final relayBody = Block();
      final forwarded = relayBody.emit(
        DirectCall(leaf, [], typeArguments: [y, x]),
      );
      relayBody.finish(Return(forwarded));
      final entry = Block();
      final called = entry.emit(
        DirectCall(relay, [], typeArguments: [.integer, .floating]),
      );
      entry.finish(Return(called));
      final prepared = prepare(
        IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(relay, [relayBody]),
          IrFunction(leaf, [leafBody]),
        ]),
        roots: [root],
      );
      final selection = prepared.selection;
      expect(selection.layouts.typeEnvironment.parametersOf(leaf), [1]);
      expect(selection.layouts.typeEnvironment.parametersOf(relay), [0]);
      final selectedLeaf = selection.functions[leaf]!;
      final selectedRelay = selection.functions[relay]!;
      expect(selectedLeaf.entryParameters, hasLength(1));
      expect(selectedRelay.entryParameters, hasLength(1));
      expect(selectedLeaf.inputsOf(reified), selectedLeaf.entryParameters);
      expect(selectedRelay.inputsOf(forwarded), selectedRelay.entryParameters);
      expect(selection.functions[root]!.inputsOf(called), hasLength(1));
      emit(prepared);
    });
  }
}
