import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/storage_promotion.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

IrProgram normalize(IrProgram p) =>
    const ProgramStoragePromotion().bind().normalize(p);

Iterable<Instruction> instructions(IrProgram p) =>
    p.functions.expand((f) => f.blocks).expand((b) => b.instructions);

Object? run(IrProgram p, List<Object?> args) =>
    IrInterpreter(p, {}).run(p.functions.first, args);

void main() {
  const one = Constant.integer(1);
  final uri = Uri.parse('memory:checked-cell');

  test('explicitly bound mutable late aliases carry branch writes', () {
    final fn = FunctionTarget(uri, 'branch', .integer, [.boolean, .integer]);
    final entry = Block(fn.parameterTypes);
    final cell = entry.emit(NewCell(CellType(.integer, isLate: true), one));
    final alias = Block([cell.type]),
        yes = Block(),
        no = Block(),
        done = Block();
    entry.finish(Jump(alias, [cell]));
    alias.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
    yes.emit(WriteCell(alias.parameters.single, entry.parameters.last));
    yes.finish(Jump(done));
    no.finish(Jump(done));
    done.finish(Return(done.emit(ReadCell(alias.parameters.single))));
    final original = IrProgram([], [
      IrFunction(fn, [entry, alias, yes, no, done]),
    ]);
    final promoted = normalize(original);
    expect(instructions(promoted).whereType<NewCell>(), isEmpty);
    expect(instructions(promoted).whereType<ReadCell>(), isEmpty);
    expect(instructions(promoted).whereType<WriteCell>(), isEmpty);
    for (final p in [original, promoted]) {
      expect(run(p, [true, 37]), 37);
      expect(run(p, [false, 37]), 1);
    }
  });

  test('bound nullable null differs from an unbound late cell', () {
    for (final bound in [false, true]) {
      final fn = FunctionTarget(
        uri,
        'nullable',
        ValueType.integer.nullable,
        [],
      );
      final b = Block();
      final c = b.emit(
        NewCell(
          CellType(ValueType.integer.nullable, isLate: true),
          bound ? const Constant.nullValue() : null,
        ),
      );
      b.finish(Return(b.emit(ReadCell(c))));
      final p = IrProgram([], [
        IrFunction(fn, [b]),
      ]);
      final promoted = normalize(p);
      expect(instructions(promoted).whereType<NewCell>().isEmpty, bound);
      for (final program in [p, promoted]) {
        if (bound) {
          expect(run(program, []), isNull);
        } else {
          expect(() => run(program, []), throwsA(anything));
        }
      }
    }
  });

  for (final atInitialization in [false, true]) {
    test(
      'wide values retain their runtime check (initial=$atInitialization)',
      () {
        final fn = FunctionTarget(uri, 'checked', .integer, [
          ValueType.dynamicType,
        ]);
        final b = Block(fn.parameterTypes);
        final wide = b.emit(
          UncheckedCast(b.parameters.single, ValueType.integer),
        );
        final c = b.emit(
          NewCell(
            CellType(.integer, isLate: true),
            atInitialization ? wide : one,
          ),
        );
        if (!atInitialization) b.emit(WriteCell(c, wide));
        b.finish(Return(b.emit(ReadCell(c))));
        final p = IrProgram([], [
          IrFunction(fn, [b]),
        ]);
        final promoted = normalize(p);
        expect(instructions(promoted).whereType<NewCell>(), hasLength(1));
        for (final program in [p, promoted]) {
          expect(run(program, [37]), 37);
          for (final value in [null, 'wrong']) {
            expect(() => run(program, [value]), throwsA(isA<TypeError>()));
          }
        }
      },
    );
  }

  for (final isLate in [false, true]) {
    test('a separately checked write retains its carrier (late=$isLate)', () {
      final fn = FunctionTarget(uri, 'cast', .integer, [ValueType.dynamicType]);
      final b = Block(fn.parameterTypes);
      final cell = b.emit(NewCell(CellType(.integer, isLate: isLate), one));
      final checked = b.emit(TypeCast(b.parameters.single, ValueType.integer));
      b.emit(WriteCell(cell, checked));
      b.finish(Return(b.emit(ReadCell(cell))));
      final original = IrProgram([], [
        IrFunction(fn, [b]),
      ]);
      final promoted = normalize(original);
      expect(instructions(promoted).whereType<TypeCast>(), hasLength(1));
      expect(instructions(promoted).whereType<WriteCell>(), hasLength(1));
      for (final p in [original, promoted]) {
        expect(run(p, [37]), 37);
        expect(() => run(p, [null]), throwsA(isA<TypeError>()));
      }
    });
  }

  test('a conflicting read carrier keeps its writes until verification', () {
    for (final isLate in [false, true]) {
      final fn = FunctionTarget(uri, 'override', .integer, [.integer]);
      final b = Block(fn.parameterTypes);
      final cell = b.emit(NewCell(CellType(.integer, isLate: isLate), one));
      b.emit(WriteCell(cell, b.parameters.single));
      final read = b.emit(ReadCell(cell));
      b.finish(Return(read));
      final body = IrFunction(fn, [
        b,
      ], execution: FunctionExecution({read: ExecutionShape.reference}));
      final program = IrProgram([], [
        body,
      ], executionShapes: ExecutionShapes.defaults);
      final normalized = normalize(program);
      expect(instructions(normalized).whereType<WriteCell>(), hasLength(1));
      expect(run(normalized, [37]), 37);
      expect(
        () => ExecutionShapes.defaults.verify(normalized.functions.single),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('contradicts its actual producer'),
          ),
        ),
      );
    }
  });

  for (final throughParameter in [false, true]) {
    test(
      'a callable can have a wider reified result (phi=$throughParameter)',
      () {
        final proof = PromotedType(ValueType.object, ValueType.integer);
        final callee = FunctionTarget(uri, 'provedResult', proof, []);
        final cb = Block()..finish(const Return(one));
        final content = FunctionType(ValueType.integer, []);
        final main = FunctionTarget(uri, 'checkedFunction', .integer, []);
        final entry = Block(), next = Block([content]);
        final callback = FunctionConstant(callee);
        expect(content.accepts(callback.type), isTrue);
        expect(content.accepts(callback.runtimeValueType), isFalse);
        entry.finish(Jump(next, [callback]));
        final source = throughParameter ? next.parameters.single : callback;
        next.emit(NewCell(CellType(content, isLate: true), source));
        next.finish(const Return(one));
        final p = IrProgram([], [
          IrFunction(main, [entry, next]),
          IrFunction(callee, [cb]),
        ]);
        final promoted = normalize(p);
        expect(instructions(promoted).whereType<NewCell>(), hasLength(1));
        for (final program in [p, promoted]) {
          expect(() => run(program, []), throwsA(isA<TypeError>()));
        }
      },
    );
  }

  test('late final, lazy initialization and mixed incoming identities retain cells', () {
    final fn = FunctionTarget(uri, 'single', .integer, []);
    final b = Block();
    final c = b.emit(
      NewCell(CellType(.integer, isLate: true, isFinal: true), one),
    );
    b.emit(WriteCell(c, const Constant.integer(4)));
    b.finish(Return(b.emit(ReadCell(c))));
    final p = IrProgram([], [
      IrFunction(fn, [b]),
    ]);
    expect(instructions(normalize(p)).whereType<NewCell>(), hasLength(1));
    expect(() => run(normalize(p), []), throwsA(anything));

    final lazy = FunctionTarget(uri, 'thunk', .integer, []);
    final lb = Block()..finish(const Return(one));
    final caller = Block();
    final delayed = caller.emit(
      NewCell(
        CellType(.integer, isLate: true),
        null,
        initializer: FunctionConstant(lazy),
      ),
    );
    caller.finish(Return(caller.emit(ReadCell(delayed))));
    final program = IrProgram([], [
      IrFunction(fn, [caller]),
      IrFunction(lazy, [lb]),
    ]);
    expect(instructions(normalize(program)).whereType<NewCell>(), hasLength(1));
    expect(run(normalize(program), []), 1);

    final mixed = FunctionTarget(uri, 'mixed', .integer, [.boolean]);
    final e = Block(mixed.parameterTypes);
    final a = e.emit(NewCell(CellType(.integer, isLate: true), one));
    final d = e.emit(NewCell(a.type as CellType, const Constant.integer(37)));
    final j = Block([a.type]);
    e.finish(Branch(e.parameters.single, Jump(j, [a]), Jump(j, [d])));
    j.finish(Return(j.emit(ReadCell(j.parameters.single))));
    final m = IrProgram([], [
      IrFunction(mixed, [e, j]),
    ]);
    expect(instructions(normalize(m)).whereType<NewCell>(), hasLength(2));
    expect(run(normalize(m), [true]), 1);
    expect(run(normalize(m), [false]), 37);
  });
}
