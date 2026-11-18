import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test('linked stack metadata has a shared address through ordinary calls', () {
    final helper = FunctionTarget(null, 'maps', .integer, []);
    final body = Block();
    final address = body.emit(StackMapAddress());
    body.finish(Return(address));
    final root = FunctionTarget(null, 'entry', .integer, []);
    final entry = Block();
    final direct = entry.emit(StackMapAddress());
    final call = entry.emit(DirectCall(helper, []));
    entry.finish(Return(call));
    final program = IrProgram([], [
      IrFunction(root, [entry]),
      IrFunction(helper, [body]),
    ]);
    final facts = ProgramFlow(program, [(target: root, arguments: [])]).facts;
    expect(facts.valueOf(direct).addresses, facts.valueOf(call).addresses);
    expect(facts.valueOf(call).addresses, hasLength(1));
    expect(facts.valueOf(call).references.isBottom, isFalse);
    expect(address.effects, isEmpty);
    expect(address.mayThrow, isFalse);
    expect(address.mapInputs((v) => v), isA<StackMapAddress>());
  });

  test('addressable empty stack tables survive default compilation and object codecs', () {
    final target = FunctionTarget(null, 'maps', .integer, []);
    final entry = Block();
    entry.finish(Return(entry.emit(StackMapAddress())));
    final program = IrProgram([], [
      IrFunction(target, [entry]),
    ]);
    for (final os in OperatingSystem.values) {
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(Target(os, .arm64)),
        X64CodeGenerator(Target(os, .x64)),
      ]) {
        final module = generator.generate(
          Compiler(generator.target).prepare(program, roots: [target]),
        );
        final ObjectFormat format = os == .macos
            ? MachO(generator.target)
            : Elf(generator.target);
        for (final current in [
          module,
          format.decodeObject(format.encodeObject(module)),
        ]) {
          expect(current.imports, isEmpty);
          final index = current.symbols.indexWhere(
            (symbol) => symbol.name == '.dartc.roots',
          );
          expect(index, isNonNegative);
          final symbol = current.symbols[index];
          final section = current.sections[symbol.section];
          expect(section.kind, SectionKind.readOnlyData);
          expect(section.alignment, greaterThanOrEqualTo(8));
          final data = ByteData.sublistView(section.bytes, symbol.offset);
          expect(data.getUint64(StackMapTable.count, .little), 0);
          expect(
            data.lengthInBytes,
            greaterThanOrEqualTo(StackMapTable.entries),
          );
          expect(
            current.relocations.where(
              (relocation) => relocation.symbol == index,
            ),
            isNotEmpty,
          );
        }
      }
    }
  });
}
