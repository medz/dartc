import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
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
              generator.generate(program, definitions: [declaration]).sections,
              isNotEmpty,
            );
          } else {
            expect(
              () => generator.generate(program, definitions: [declaration]),
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
            () => generator.generate(program, definitions: [declaration]),
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
      test('$target rejects aliased local cells and late initialization', () {
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
          expect(
            () => generator.generate(program, definitions: [declaration]),
            throwsUnsupportedError,
          );
        }
      });
    }
  }
}
