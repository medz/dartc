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
      test(
        '$target discovers globals reached through generated error helpers',
        () {
          final uri = Uri.parse('memory:helper-globals');
          final initialize = FunctionTarget(uri, 'initialize', .integer, []);
          final initial = Block([])..finish(Return(const Constant.integer(7)));
          final slot = GlobalVariable(
            uri,
            'state',
            .integer,
            initializer: initialize,
          );
          final error = FunctionTarget(
            Uri.parse('dart:core'),
            'new',
            .voidType,
            [.string],
            owner: ValueType.unsupportedError,
            kind: .initializer,
          );
          final errorEntry = Block(error.parameterTypes);
          errorEntry.emit(LoadGlobal(slot));
          errorEntry.finish(const Return());
          final convert = FunctionTarget(uri, 'convert', .integer, [.floating]);
          final entry = Block(convert.parameterTypes);
          entry.finish(
            Return(
              entry.emit(NumericToInt(entry.parameters.single, .truncate)),
            ),
          );
          final program = IrProgram(
            [
              IrClass(ValueType.error, []),
              IrClass(ValueType.unsupportedError, [], constructors: [error]),
            ],
            [
              IrFunction(initialize, [initial]),
              IrFunction(error, [errorEntry]),
              IrFunction(convert, [entry]),
            ],
            globals: [slot],
          );
          final module = generator.generate(program, definitions: [convert]);
          expect(
            module.symbols.any((symbol) => symbol.name == '.dartc.globals'),
            isTrue,
          );
        },
      );
      test('$target checks global storage and error-body dependencies', () {
        for (final (type, late, final_, initialized) in [
          (ValueType.integer.nullable, false, false, true),
          (ValueType.number, false, false, true),
          (ValueType.integer, true, false, false),
          (ValueType.integer, true, false, true),
          (ValueType.integer, false, true, true),
        ]) {
          final uri = Uri.parse('memory:globals');
          final init = FunctionTarget(uri, 'init', type, []);
          final initial = Block([])..finish(Return(const Constant.integer(7)));
          final global = GlobalVariable(
            uri,
            'value',
            type,
            isLate: late,
            isFinal: final_,
            initializer: initialized ? init : null,
          );
          final read = FunctionTarget(uri, 'read', type, []);
          final entry = Block([]);
          entry.finish(Return(entry.emit(LoadGlobal(global))));
          final program = IrProgram(
            [],
            [
              IrFunction(init, [initial]),
              IrFunction(read, [entry]),
            ],
            globals: [global],
          );
          if (!final_ && (!late || initialized)) {
            expect(
              generator
                  .generate(program, definitions: program.reachableFrom([read]))
                  .sections,
              isNotEmpty,
            );
            continue;
          }
          expect(
            () => generator.generate(
              program,
              definitions: program.reachableFrom([read]),
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'reason',
                contains(late || final_ ? 'LateError constructor' : 'global'),
              ),
            ),
          );
        }
      });
    }
  }
}
