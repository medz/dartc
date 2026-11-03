import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final f = FunctionTarget(.parse('memory:test'), 'f', .integer, [.boolean]);
  const Constant one = .integer(1);

  test(
    'a finished graph retains its inputs when caller-owned lists change',
    () {
      // #region block_arguments
      final types = <ValueType>[.integer];
      final target = FunctionTarget(
        .parse('memory:example'),
        'identity',
        .integer,
        types,
      );
      final entry = Block(types), exit = Block(types);
      final arguments = [entry.parameters.single];
      entry.finish(Jump(exit, arguments));
      exit.finish(Return(exit.parameters.single));
      final blocks = [entry, exit];
      final function = IrFunction(target, blocks);
      // #endregion block_arguments

      types.clear();
      arguments.clear();
      blocks.clear();
      expect(function.blocks, [entry, exit]);
      expect(target.parameterTypes.single, entry.parameters.single.type);
      expect(
        (entry.end as Jump).arguments.single,
        same(entry.parameters.single),
      );
    },
  );

  test('a branch-local value cannot escape through the other arm', () {
    final entry = Block(f.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block();
    entry.finish(Branch(entry.parameters.single, .new(yes), .new(no)));
    final temporary = yes.emit(IntBinary(.add, one, one));
    yes.finish(Jump(join));
    no.finish(Jump(join));
    join.finish(Return(temporary));
    expect(() => IrFunction(f, [entry, yes, no, join]), throwsStateError);
  });

  test('uses before definition and foreign block parameters are rejected', () {
    final entry = Block(f.parameterTypes);
    final next = IntBinary(.add, one, one);
    final result = entry.emit(IntBinary(.subtract, next, one));
    entry.emit(next);
    entry.finish(Return(result));
    expect(() => IrFunction(f, [entry]), throwsStateError);

    final foreign = Block([.integer]);
    final other = Block(f.parameterTypes)
      ..finish(Return(foreign.parameters.single));
    expect(() => IrFunction(f, [other]), throwsStateError);
  });

  test('edges and function returns check arity, type and block membership', () {
    final join = Block([.integer])..finish(const Return(one));
    expect(() => Jump(join), throwsArgumentError);
    expect(
      () => Jump(join, [const Constant.boolean(true)]),
      throwsArgumentError,
    );
    final entry = Block(f.parameterTypes)..finish(Jump(join, [one]));
    expect(() => IrFunction(f, [entry]), throwsStateError);
    final wrongReturn = Block(f.parameterTypes)..finish(const Return());
    expect(() => IrFunction(f, [wrongReturn]), throwsStateError);
    expect(() => IrFunction(f, [entry, join]), returnsNormally);
    expect(() => join.emit(IntBinary(.add, one, one)), throwsStateError);
  });

  test('void accepts incoming values but cannot narrow an entry signature', () {
    final target = FunctionTarget(f.library, 'forward', .voidType, [.voidType]);
    final entry = Block(target.parameterTypes);
    final narrowed = Block([.integer])..finish(const Return(one));
    expect(() => Jump(entry, [one]), returnsNormally);
    expect(() => Jump(narrowed, entry.parameters), throwsArgumentError);
    expect(() => IrFunction(target, [narrowed]), throwsArgumentError);
  });

  test('record shape and slots stay fixed when caller-owned fields change', () {
    final names = <String, ValueType>{'z': .string, 'a': .integer};
    final type = RecordType([.boolean], names);
    names.clear();
    expect(type.slots, {r'$1': 0, 'a': 1, 'z': 2});
    expect(type.dartName, '(bool, {int a, String z})');
    final reordered = RecordType([.boolean], {'a': .integer, 'z': .string});
    expect(type, reordered);
    expect(type.hashCode, reordered.hashCode);
    final wide = RecordType([.boolean], {'a': .number, 'z': .object});
    expect(wide.accepts(type), isTrue);
    expect(type.accepts(wide), isFalse);
    expect(wide.accepts(RecordType([.boolean], {'a': .integer})), isFalse);
    expect(
      () => RecordType([.boolean], {r'$1': .integer}),
      throwsArgumentError,
    );
    expect(() => MakeRecord(type, [one]), throwsArgumentError);
    expect(() => RecordGet(one, 0), throwsArgumentError);
    final record = MakeRecord(type, [
      const Constant.boolean(false),
      one,
      const Constant.string('z'),
    ]);
    expect(RecordGet(record, 1).type, ValueType.integer);
    expect(() => RecordGet(record, 3), throwsRangeError);
  });

  test(
    'nominal owners distinguish fields, allocation and in-place initialization',
    () {
      final api = ClassType(f.library, 'Item', isAbstract: true);
      final sub = ClassType(f.library, 'Sub', interfaces: [api]);
      final other = ClassType(Uri.parse('memory:other'), 'Item');
      expect(api.accepts(sub), isTrue);
      expect(other.accepts(sub), isFalse);
      final field = InstanceField(sub, 'x', .integer, isFinal: true);
      expect(() => IrClass(other, [field]), throwsArgumentError);
      final init = FunctionTarget(
        sub.library,
        'new',
        .voidType,
        [],
        owner: sub,
        kind: .initializer,
      );
      final abstractInit = FunctionTarget(
        api.library,
        'new',
        .voidType,
        [],
        owner: api,
        kind: .initializer,
      );
      expect(() => Construct(abstractInit, []), throwsArgumentError);
      final legal = Block(init.parameterTypes);
      legal.emit(StoreField(field, legal.parameters.single, one));
      legal.finish(const Return());
      expect(
        () => IrProgram(
          [
            IrClass(sub, [field]),
          ],
          [
            IrFunction(init, [legal]),
          ],
        ),
        returnsNormally,
      );
      final create = FunctionTarget(f.library, 'create', sub, []);
      for (final initializeAgain in [true, false]) {
        final entry = Block();
        final object = entry.emit(Construct(init, []));
        entry.emit(
          initializeAgain
              ? DirectCall(init, [object])
              : StoreField(field, object, one),
        );
        entry.finish(Return(object));
        expect(() => IrFunction(create, [entry]), throwsStateError);
      }
    },
  );

  test('a protected operation and its exception have distinct SSA edges', () {
    final target = FunctionTarget(f.library, 'invoke', .object, [.object]);
    final entry = Block(target.parameterTypes);
    final normal = Block([.integer]), handler = Block([.object, .stackTrace]);
    final cast = TypeCast(entry.parameters.single, .integer);
    final returned = Jump(normal, [cast]);
    final caught = Jump(handler, [
      UnwindValue.exception,
      UnwindValue.stackTrace,
    ]);
    entry.finish(Invoke(cast, onReturn: returned, onThrow: caught));
    normal.finish(Return(normal.parameters.single));
    handler.finish(Return(handler.parameters.first));
    final graph = IrFunction(target, [entry, normal, handler]);
    final out = StringBuffer();
    graph.writeTo(out);
    expect(out.toString(), contains('unwind b2(exception, stackTrace)'));

    final bad = Block(target.parameterTypes);
    final checked = TypeCast(bad.parameters.single, .integer);
    bad.finish(
      Invoke(
        checked,
        onReturn: Jump(normal, [checked]),
        onThrow: Jump(handler, [checked, UnwindValue.stackTrace]),
      ),
    );
    expect(() => IrFunction(target, [bad, normal, handler]), throwsStateError);
    final misplaced = Block(target.parameterTypes)
      ..finish(Return(UnwindValue.exception));
    expect(() => IrFunction(target, [misplaced]), throwsStateError);
    expect(
      () => Invoke(cast, onReturn: null, onThrow: caught),
      throwsArgumentError,
    );
    expect(() => Throw(one, stackTrace: one), throwsArgumentError);
  });

  test('a nullable value narrows only on the matching null-test edge', () {
    final maybeInt = ValueType.integer.nullable;
    final target = FunctionTarget(f.library, 'pick', .number, [maybeInt]);
    final join = Block([.number])..finish(const Return(one));
    final entry = Block(target.parameterTypes);
    final input = entry.parameters.single;
    expect(() => Jump(join, [input]), throwsArgumentError);
    final test = entry.emit(TypeTest(input, .nullType));
    entry.finish(
      Branch(test, .new(join, [one]), .new(join, [test.refinement(false)!])),
    );
    expect(() => IrFunction(target, [entry, join]), returnsNormally);

    final wrong = Block([maybeInt]);
    final inverted = wrong.emit(
      TypeTest(wrong.parameters.single, .nullType, negated: true),
    );
    final illicit = Jump(join, [inverted.refinement(true)!]);
    wrong.finish(Branch(inverted, illicit, illicit));
    expect(() => IrFunction(target, [wrong, join]), throwsStateError);
    expect(() => Unreachable(one), throwsArgumentError);
    expect(() => Throw(input), throwsArgumentError);
    final dead = Block(target.parameterTypes);
    dead.emit(NullCheck(const Constant.nullValue()));
    dead.finish(const Return(one));
    expect(() => IrFunction(target, [dead]), throwsStateError);
  });
}
