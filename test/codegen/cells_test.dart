import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/cell_initialization.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final uri = Uri.parse('memory:source-cells');
  final target = FunctionTarget(uri, 'source', .integer, [.boolean]);
  final capture = FunctionTarget(
    uri,
    'capture',
    .integer,
    [],
    kind: .closure,
    enclosing: target,
    sourceOffset: 1,
    captures: [CellType(.integer)],
  );
  test('unused closure capture does not initialize a conditional cell', () {
    final entry = Block(target.parameterTypes),
        yes = Block(),
        no = Block(),
        done = Block();
    final cell = entry.emit(NewCell(CellType(.integer), null));
    entry.emit(MakeClosure(capture, [cell]));
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    yes.emit(WriteCell(cell, const Constant.integer(1)));
    yes.finish(Jump(done));
    no.finish(Jump(done));
    done.finish(Return(done.emit(ReadCell(cell))));
    expect(
      () => checkCellInitialization(IrFunction(target, [entry, yes, no, done])),
      throwsUnsupportedError,
    );
  });
  test('fresh captured loop cell does not inherit previous initialization', () {
    final entry = Block(target.parameterTypes),
        loop = Block(),
        done = Block([.integer]);
    entry.finish(Jump(loop));
    final cell = loop.emit(NewCell(CellType(.integer), null));
    loop.emit(MakeClosure(capture, [cell]));
    final value = loop.emit(ReadCell(cell));
    loop.emit(WriteCell(cell, const Constant.integer(1)));
    loop.finish(
      Branch(entry.parameters.single, Jump(loop), Jump(done, [value])),
    );
    done.finish(Return(done.parameters.single));
    expect(
      () => checkCellInitialization(IrFunction(target, [entry, loop, done])),
      throwsUnsupportedError,
    );
  });
  test(
    'a fresh loop cell does not invalidate the previous iteration alias',
    () {
      final entry = Block(target.parameterTypes);
      final loop = Block([CellType(.integer)]), done = Block([.integer]);
      final seed = entry.emit(
        NewCell(CellType(.integer), const Constant.integer(1)),
      );
      entry.finish(Jump(loop, [seed]));
      final next = loop.emit(NewCell(CellType(.integer), null));
      final previous = loop.emit(ReadCell(loop.parameters.single));
      loop.emit(WriteCell(next, previous));
      loop.finish(
        Branch(
          entry.parameters.single,
          Jump(loop, [next]),
          Jump(done, [previous]),
        ),
      );
      done.finish(Return(done.parameters.single));
      checkCellInitialization(IrFunction(target, [entry, loop, done]));
    },
  );
  test('copying an unbound cell is independent of later source writes', () {
    for (final initializeCopy in [false, true]) {
      final entry = Block(target.parameterTypes);
      final source = entry.emit(NewCell(CellType(.integer), null));
      final copy = entry.emit(CopyCell(source));
      entry.emit(WriteCell(source, const Constant.integer(1)));
      if (initializeCopy) {
        entry.emit(WriteCell(copy, const Constant.integer(2)));
      }
      entry.finish(Return(entry.emit(ReadCell(copy))));
      final function = IrFunction(target, [entry]);
      if (initializeCopy) {
        checkCellInitialization(function);
      } else {
        expect(() => checkCellInitialization(function), throwsUnsupportedError);
      }
    }
  });
  test('merged aliases require every incoming value to be initialized', () {
    for (final both in [false, true]) {
      final entry = Block(target.parameterTypes), yes = Block(), no = Block();
      final done = Block([CellType(.integer)]);
      final left = entry.emit(
        NewCell(CellType(.integer), const Constant.integer(1)),
      );
      final right = entry.emit(
        NewCell(CellType(.integer), both ? const Constant.integer(2) : null),
      );
      entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
      yes.finish(Jump(done, [left]));
      no.finish(Jump(done, [right]));
      done.finish(Return(done.emit(ReadCell(done.parameters.single))));
      final function = IrFunction(target, [entry, yes, no, done]);
      if (both) {
        checkCellInitialization(function);
      } else {
        expect(() => checkCellInitialization(function), throwsUnsupportedError);
      }
    }
  });
  test('a unique alias write initializes the shared source', () {
    final entry = Block(target.parameterTypes),
        next = Block([CellType(.integer)]);
    final cell = entry.emit(NewCell(CellType(.integer), null));
    entry.finish(Jump(next, [cell]));
    next.emit(WriteCell(next.parameters.single, const Constant.integer(1)));
    next.finish(Return(next.emit(ReadCell(cell))));
    checkCellInitialization(IrFunction(target, [entry, next]));
  });
  test('writing a merged alias does not initialize every possible source', () {
    final entry = Block(target.parameterTypes), yes = Block(), no = Block();
    final done = Block([CellType(.integer)]);
    final left = entry.emit(NewCell(CellType(.integer), null));
    final right = entry.emit(NewCell(CellType(.integer), null));
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    yes.finish(Jump(done, [left]));
    no.finish(Jump(done, [right]));
    done.emit(WriteCell(done.parameters.single, const Constant.integer(1)));
    done.finish(Return(done.emit(ReadCell(left))));
    expect(
      () => checkCellInitialization(IrFunction(target, [entry, yes, no, done])),
      throwsUnsupportedError,
    );
  });
  test('closure entry captures and their copies retain initialization', () {
    final entry = Block(capture.parameterTypes);
    final copy = entry.emit(CopyCell(entry.parameters[1]));
    entry.finish(Return(entry.emit(ReadCell(copy))));
    checkCellInitialization(IrFunction(capture, [entry]));
  });
  test('normal continuation writes do not initialize an exceptional path', () {
    final entry = Block(target.parameterTypes),
        done = Block(),
        failed = Block();
    final cell = entry.emit(NewCell(CellType(.integer), null));
    final callee = FunctionTarget(uri, 'mayThrow', .integer, []);
    entry.finish(
      Invoke(
        DirectCall(callee, []),
        onReturn: Jump(done),
        onThrow: Jump(failed),
      ),
    );
    done.emit(WriteCell(cell, const Constant.integer(1)));
    done.finish(Return(done.emit(ReadCell(cell))));
    failed.finish(Return(failed.emit(ReadCell(cell))));
    expect(
      () => checkCellInitialization(IrFunction(target, [entry, done, failed])),
      throwsUnsupportedError,
    );
  });
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final CodeGenerator generator = arch == .arm64
          ? Arm64CodeGenerator(target)
          : X64CodeGenerator(target);
      final declaration = FunctionTarget(
        Uri.parse('memory:cells'),
        'read',
        .integer,
        [.boolean],
      );
      test(
        '$target rejects uninitialized cells promoted by unused closures',
        () {
          final child = FunctionTarget(
            declaration.library,
            'child',
            .integer,
            [],
            kind: .closure,
            enclosing: declaration,
            sourceOffset: 1,
            captures: [CellType(.integer)],
          );
          final entry = Block(declaration.parameterTypes);
          final cell = entry.emit(NewCell(CellType(.integer), null));
          entry.emit(MakeClosure(child, [cell]));
          entry.finish(Return(entry.emit(ReadCell(cell))));
          final childEntry = Block(child.parameterTypes)
            ..finish(const Return(Constant.integer(1)));
          final program = IrProgram([], [
            IrFunction(declaration, [entry]),
            IrFunction(child, [childEntry]),
          ]);
          expect(
            () => generator.generate(
              program,
              runtime: heapRuntime,
              definitions: [declaration, child],
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (error) => error.message,
                'reason',
                contains('before initialization'),
              ),
            ),
          );
        },
      );
      test('$target requires every incoming path to initialize a local', () {
        for (final (initial, both) in [
          (false, false),
          (false, true),
          (true, false),
        ]) {
          final entry = Block(declaration.parameterTypes),
              yes = Block(),
              no = Block(),
              done = Block();
          final cell = entry.emit(
            NewCell(
              CellType(.integer),
              initial ? const Constant.integer(7) : null,
            ),
          );
          entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
          yes.emit(WriteCell(cell, const Constant.integer(1)));
          yes.finish(Jump(done));
          if (both) no.emit(WriteCell(cell, const Constant.integer(2)));
          no.finish(Jump(done));
          done.finish(Return(done.emit(ReadCell(cell))));
          final program = IrProgram([], [
            IrFunction(declaration, [entry, yes, no, done]),
          ]);
          if (initial || both) {
            expect(
              generator
                  .generate(
                    program,
                    runtime: heapRuntime,
                    definitions: [declaration],
                  )
                  .sections,
              isNotEmpty,
            );
          } else {
            expect(
              () => generator.generate(
                program,
                runtime: heapRuntime,
                definitions: [declaration],
              ),
              throwsA(
                isA<UnsupportedError>().having(
                  (e) => e.message,
                  'reason',
                  contains('before initialization'),
                ),
              ),
            );
          }
        }
      });
      test(
        '$target does not use a previous iteration to initialize a fresh cell',
        () {
          final entry = Block(declaration.parameterTypes),
              loop = Block(),
              done = Block([.integer]);
          entry.finish(Jump(loop));
          final cell = loop.emit(NewCell(CellType(.integer), null));
          final value = loop.emit(ReadCell(cell));
          loop.emit(WriteCell(cell, const Constant.integer(1)));
          loop.finish(
            Branch(entry.parameters.single, Jump(loop), Jump(done, [value])),
          );
          done.finish(Return(done.parameters.single));
          final program = IrProgram([], [
            IrFunction(declaration, [entry, loop, done]),
          ]);
          expect(
            () => generator.generate(
              program,
              runtime: heapRuntime,
              definitions: [declaration],
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'reason',
                contains('before initialization'),
              ),
            ),
          );
        },
      );
      test('$target supports aliases and requires the SDK late error body', () {
        for (final late in [false, true]) {
          final entry = Block(declaration.parameterTypes);
          final cell = entry.emit(
            NewCell(
              CellType(.integer, isLate: late),
              const Constant.integer(1),
            ),
          );
          final next = Block([cell.type]);
          entry.finish(Jump(next, [cell]));
          next.finish(Return(next.emit(ReadCell(next.parameters.single))));
          final program = IrProgram([], [
            IrFunction(declaration, [entry, next]),
          ]);
          if (late) {
            expect(
              () => generator.generate(
                program,
                runtime: heapRuntime,
                definitions: [declaration],
              ),
              throwsA(
                isA<UnsupportedError>().having(
                  (error) => error.message,
                  'reason',
                  contains('LateError constructor'),
                ),
              ),
            );
          } else {
            expect(
              generator
                  .generate(
                    program,
                    runtime: heapRuntime,
                    definitions: [declaration],
                  )
                  .sections,
              isNotEmpty,
            );
          }
        }
      });
    }
  }
}
