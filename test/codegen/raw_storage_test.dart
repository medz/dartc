import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/cell_initialization.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:raw-storage');
  final owner = ClassType(uri, 'Storage');
  final left = InstanceField(
    owner,
    'left',
    .integer.nullable,
    initiallyUnbound: true,
  );
  final right = InstanceField(
    owner,
    'right',
    .integer.nullable,
    initiallyUnbound: true,
  );
  final initialize = FunctionTarget(
    uri,
    'new',
    .voidType,
    [],
    owner: owner,
    kind: .initializer,
  );
  final init = IrFunction(initialize, [
    Block(initialize.parameterTypes)..finish(const Return()),
  ]);
  final declaration = IrClass(owner, [left, right], constructors: [initialize]);
  IrProgram program(
    IrFunction body, {
    Iterable<IrExternal> externals = const [],
  }) => IrProgram([declaration], [body, init], externals: externals);

  test(
    'nullable raw storage distinguishes unbound bytes from assigned null',
    () {
      for (final assigned in [false, true]) {
        final root = FunctionTarget(uri, 'nullable', .integer.nullable, []);
        final entry = Block();
        final object = entry.emit(Construct(initialize, []));
        if (assigned) {
          entry.emit(StoreField(left, object, const Constant.nullValue()));
        }
        entry.finish(Return(entry.emit(LoadField(left, object))));
        final body = IrFunction(root, [entry]), input = program(body);
        if (assigned) {
          cellInitializationRequirements(input);
          expect(IrInterpreter(input, {}).run(body, []), isNull);
          expect(
            ProgramFlow(input, [
              (target: root, arguments: <FlowValue>[]),
            ]).facts.returnedBy(root).constant,
            const Constant.nullValue(),
          );
        } else {
          expect(
            () => cellInitializationRequirements(input),
            throwsUnsupportedError,
          );
          expect(
            () => IrInterpreter(input, {}).run(body, []),
            throwsStateError,
          );
          expect(
            ProgramFlow(input, [
              (target: root, arguments: <FlowValue>[]),
            ]).facts.returnedBy(root).isBottom,
            isTrue,
          );
        }
      }
    },
  );

  test('initialization belongs to the exact field, not the receiver class', () {
    final root = FunctionTarget(uri, 'twoSlots', .integer.nullable, []);
    final entry = Block();
    final object = entry.emit(Construct(initialize, []));
    entry.emit(StoreField(left, object, const Constant.integer(42)));
    entry.finish(Return(entry.emit(LoadField(right, object))));
    expect(
      () => cellInitializationRequirements(program(IrFunction(root, [entry]))),
      throwsUnsupportedError,
    );
  });

  test('copying unbound raw storage preserves unbound instead of null', () {
    for (final assigned in [false, true]) {
      final root = FunctionTarget(uri, 'copy', .integer.nullable, []);
      final entry = Block();
      final source = entry.emit(Construct(initialize, []));
      if (assigned) {
        entry.emit(StoreField(left, source, const Constant.nullValue()));
      }
      final destination = entry.emit(Construct(initialize, []));
      entry.emit(InitializeStorageField(left, destination, source));
      entry.finish(Return(entry.emit(LoadField(left, destination))));
      final body = IrFunction(root, [entry]), input = program(body);
      final facts = ProgramFlow(input, [
        (target: root, arguments: <FlowValue>[]),
      ]).facts;
      if (assigned) {
        cellInitializationRequirements(input);
        expect(facts.returnedBy(root).constant, const Constant.nullValue());
        expect(IrInterpreter(input, {}).run(body, []), isNull);
      } else {
        expect(
          () => cellInitializationRequirements(input),
          throwsUnsupportedError,
        );
        expect(facts.returnedBy(root).isBottom, isTrue);
      }
    }
  });

  for (final prior in ['write', 'publish', 'reference', 'copy']) {
    test('initial storage copy rejects destination after $prior', () {
      final opaque = FunctionTarget(uri, 'opaque', .voidType, [owner]);
      final root = FunctionTarget(uri, 'lifetime', .voidType, []);
      final entry = Block();
      final source = entry.emit(Construct(initialize, []));
      final destination = entry.emit(Construct(initialize, []));
      switch (prior) {
        case 'write':
          entry.emit(StoreField(left, destination, const Constant.integer(73)));
        case 'publish':
          entry.emit(DirectCall(opaque, [destination]));
        case 'reference':
          entry.emit(ReferenceAddress(destination));
        case 'copy':
          entry.emit(InitializeStorageField(left, destination, source));
      }
      entry.emit(InitializeStorageField(left, destination, source));
      entry.finish(const Return());
      final input = program(
        IrFunction(root, [entry]),
        externals: [IrExternal(opaque)],
      );
      expect(
        () => cellInitializationRequirements(input),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'reason',
            contains('fresh, unbound, unpublished'),
          ),
        ),
      );
    });
  }

  test('a call cannot restore unpublished storage by throwing', () {
    final publish = FunctionTarget(uri, 'publishThenThrow', .never, [owner]);
    final root = FunctionTarget(uri, 'exceptionalPublication', .voidType, []);
    final entry = Block(), handler = Block();
    final source = entry.emit(Construct(initialize, []));
    final destination = entry.emit(Construct(initialize, []));
    final call = DirectCall(publish, [destination]);
    entry.finish(Invoke(call, onReturn: null, onThrow: Jump(handler)));
    handler.emit(InitializeStorageField(left, destination, source));
    handler.finish(const Return());
    final input = program(
      IrFunction(root, [entry, handler]),
      externals: [IrExternal(publish)],
    );
    expect(() => cellInitializationRequirements(input), throwsUnsupportedError);
  });

  test('an opaque parameter is not a fresh initialization destination', () {
    final root = FunctionTarget(uri, 'opaqueDestination', .voidType, [
      owner,
      owner,
    ]);
    final entry = Block(root.parameterTypes);
    entry.emit(
      InitializeStorageField(
        left,
        entry.parameters.first,
        entry.parameters.last,
      ),
    );
    entry.finish(const Return());
    expect(
      () => cellInitializationRequirements(program(IrFunction(root, [entry]))),
      throwsUnsupportedError,
    );
  });

  test('a fresh copy followed by assignment preserves independent aliases', () {
    final root = FunctionTarget(uri, 'independent', .integer.nullable, []);
    final entry = Block();
    final source = entry.emit(Construct(initialize, []));
    final destination = entry.emit(Construct(initialize, []));
    entry.emit(InitializeStorageField(left, destination, source));
    entry.emit(StoreField(left, source, const Constant.integer(9)));
    entry.emit(StoreField(left, destination, const Constant.integer(7)));
    entry.finish(Return(entry.emit(LoadField(left, destination))));
    final input = program(IrFunction(root, [entry]));
    cellInitializationRequirements(input);
    final entries = [(target: root, arguments: <FlowValue>[])];
    final optimized = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramStorageElimination(),
      DirectCallInlining(),
    ]).run(input, entries);
    cellInitializationRequirements(optimized.program);
    expect(optimized.returnedBy(root).constant, const Constant.integer(7));
    expect(
      IrInterpreter(
        optimized.program,
        {},
      ).run(optimized.program.implementationOf(root)! as IrFunction, []),
      7,
    );
  });
}
