import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test('module data addresses preserve identity and loader permissions on every target', () {
    final shared = NativeData([1, 2, 3], alignment: 4);
    final equal = NativeData([1, 2, 3], alignment: 8);
    final zeros = NativeData(List.filled(64, 0), alignment: 8);
    final readonly = NativeData([1, 2, 3], alignment: 16, writable: false);
    final readonlyZeros = NativeData(
      List.filled(8, 0),
      alignment: 8,
      writable: false,
    );
    final entries = {
      'shared': shared,
      'equal': equal,
      'again': shared,
      'zeros': zeros,
      'readonly': readonly,
      'readonlyZeros': readonlyZeros,
    };
    final targets = <String, FunctionTarget>{};
    final functions = <IrFunction>[];
    for (final MapEntry(key: name, value: declaration) in entries.entries) {
      final target = FunctionTarget(null, name, .integer, []);
      final entry = Block();
      entry.finish(Return(entry.emit(NativeDataAddress(declaration))));
      targets[name] = target;
      functions.add(IrFunction(target, [entry]));
    }
    final dead = Block();
    dead.finish(Return(dead.emit(NativeDataAddress(NativeData([99])))));
    functions.add(
      IrFunction(FunctionTarget(null, 'unused', .integer, []), [dead]),
    );
    final program = IrProgram([], functions);
    for (final os in OperatingSystem.values) {
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(Target(os, .arm64)),
        X64CodeGenerator(Target(os, .x64)),
      ]) {
        final module = generator.generate(
          Compiler(generator.target).prepare(program, roots: targets.values),
        );
        expect(module.imports, isEmpty);
        expect(
          module.sections.where((section) => section.kind != .code),
          hasLength(3),
        );
        final ObjectFormat format = os == .macos
            ? MachO(generator.target)
            : Elf(generator.target);
        for (final current in [
          module,
          format.decodeObject(format.encodeObject(module)),
        ]) {
          final storage = <NativeData, Symbol>{};
          for (final MapEntry(key: name, value: data) in entries.entries) {
            final function = current.symbols.singleWhere(
              (symbol) => symbol.name == name,
            );
            final end = function.size != null
                ? function.offset + function.size!
                : current.symbols
                      .where(
                        (symbol) =>
                            symbol.section == function.section &&
                            symbol.offset > function.offset,
                      )
                      .map((symbol) => symbol.offset)
                      .fold(
                        current.sections[function.section].size,
                        (left, right) => left < right ? left : right,
                      );
            final references = current.relocations.where(
              (relocation) =>
                  relocation.section == function.section &&
                  relocation.offset >= function.offset &&
                  relocation.offset < end,
            );
            final address = references
                .map((relocation) => relocation.symbol)
                .toSet()
                .single;
            final symbol = current.symbols[address];
            if (storage[data] case final previous?) {
              expect(symbol, same(previous));
            } else {
              storage[data] = symbol;
            }
            final section = current.sections[symbol.section];
            expect(symbol.binding, SymbolBinding.local);
            expect(symbol.offset % data.alignment, 0);
            expect(section.alignment, greaterThanOrEqualTo(data.alignment));
            expect(
              section.kind,
              !data.writable
                  ? SectionKind.readOnlyData
                  : data.bytes.every((byte) => byte == 0)
                  ? SectionKind.zeroFill
                  : SectionKind.data,
            );
            if (section.kind == .zeroFill) {
              expect(section.bytes, isEmpty);
              expect(
                section.size,
                greaterThanOrEqualTo(symbol.offset + data.bytes.length),
              );
            } else {
              expect(
                section.bytes.sublist(
                  symbol.offset,
                  symbol.offset + data.bytes.length,
                ),
                data.bytes,
              );
            }
          }
          expect(storage, hasLength(5));
          expect(
            storage.values
                .map((symbol) => (symbol.section, symbol.offset))
                .toSet(),
            hasLength(5),
          );
          expect(
            current.symbols.where((symbol) => symbol.name == 'unused'),
            isEmpty,
          );
          expect(
            current.symbols.where(
              (symbol) => symbol.name.startsWith('.dartc.data'),
            ),
            hasLength(5),
          );
        }
      }
    }
  });
}
