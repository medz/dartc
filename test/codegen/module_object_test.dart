import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final type = ClassType(null, 'ModuleState');
  final number = InstanceField(type, 'number', .integer);
  final strong = InstanceField(type, 'strong', .object.nullable);
  final weak = InstanceField(type, 'weak', .object.nullable);
  final key = InstanceField(type, 'key', .object.nullable);
  final value = InstanceField(type, 'value', .object.nullable);
  final declaration = IrClass(
    type,
    [number, strong, weak, key, value],
    weakFields: {weak},
    ephemerons: {key: value},
  );
  final initial = {
    number: const Constant.integer(-73),
    strong: const Constant.string('retained'),
    weak: const Constant.nullValue(),
  };

  test('mutable module encoding preserves headers, reference relocations and all tracing modes', () {
    final layouts = ProgramLayout([
      declaration,
    ], nativeLayout: NativeLayout(const Target(.linux, .arm64)));
    final constants = ConstantData(layouts, 0);
    final module = ModuleObject(type, initialFields: initial);
    final image = constants.moduleObjectData(module);
    expect(constants.moduleObjectData(module), same(image));
    final bytes = ByteData.sublistView(image.bytes);
    expect(bytes.lengthInBytes, 80);
    expect(bytes.getInt64(ObjectHeader.sizeOffset, .little), 80);
    expect(bytes.getInt64(ObjectHeader.pageOffset, .little), 0);
    expect(bytes.getInt64(40, .little), -73);
    for (final offset in [48, 56, 64, 72]) {
      expect(bytes.getInt64(offset, .little), 0);
    }
    expect(image.references.map((ref) => ref.offset).toSet(), {0, 8, 48});
    expect(() => image.bytes[40] = 0, throwsUnsupportedError);
    final descriptor = image.references.singleWhere((ref) => ref.offset == 0);
    final symbol = constants.symbols[descriptor.symbol];
    final words = ByteData.sublistView(constants.finish().bytes);
    // Header type and strong slot are traced; weak and conditional slots have
    // their own descriptor lists and cannot accidentally become strong roots.
    final expected = [80, 2, 8, 48, 0, 0, 1, 1, 56, 64, 72];
    expect([
      for (var i = 0; i < expected.length; i++)
        words.getInt64(symbol.offset + i * 8, .little),
    ], expected);
  });

  test('module declarations retain distinct mutable addresses and a complete root table across targets', () {
    final shared = ModuleObject(type, initialFields: initial);
    final equal = ModuleObject(type, initialFields: initial);
    final entries = {'shared': shared, 'equal': equal, 'again': shared};
    final roots = <FunctionTarget>[];
    final functions = <IrFunction>[];
    for (final MapEntry(key: name, value: module) in entries.entries) {
      final target = FunctionTarget(null, name, .integer, []);
      final block = Block();
      block.finish(
        Return(
          block.emit(
            ReferenceAddress(block.emit(ModuleObjectReference(module))),
          ),
        ),
      );
      roots.add(target);
      functions.add(IrFunction(target, [block]));
    }
    final registry = FunctionTarget(null, 'registry', .integer, []);
    final table = Block();
    table.finish(Return(table.emit(ModuleRootsAddress())));
    roots.add(registry);
    functions.add(IrFunction(registry, [table]));
    final dead = Block();
    dead.finish(Return(dead.emit(ModuleObjectReference(ModuleObject(type)))));
    functions.add(IrFunction(FunctionTarget(null, 'unused', type, []), [dead]));
    final program = IrProgram([declaration], functions);
    for (final os in OperatingSystem.values) {
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(Target(os, .arm64)),
        X64CodeGenerator(Target(os, .x64)),
      ]) {
        final module = generator.generate(
          Compiler(generator.target).prepare(program, roots: roots),
        );
        final ObjectFormat format = os == .macos
            ? MachO(generator.target)
            : Elf(generator.target);
        for (final current in [
          module,
          format.decodeObject(format.encodeObject(module)),
        ]) {
          final objects = current.symbols
              .where((s) => s.name.startsWith('.dartc.object'))
              .toList();
          expect(objects, hasLength(2));
          expect(
            objects.map((s) => (s.section, s.offset)).toSet(),
            hasLength(2),
          );
          final referenced = <ModuleObject, Symbol>{};
          for (final MapEntry(key: name, value: source) in entries.entries) {
            final function = current.symbols.singleWhere((s) => s.name == name);
            final end = function.size != null
                ? function.offset + function.size!
                : current.symbols
                      .where(
                        (s) =>
                            s.section == function.section &&
                            s.offset > function.offset,
                      )
                      .map((s) => s.offset)
                      .fold(
                        current.sections[function.section].size,
                        (a, b) => a < b ? a : b,
                      );
            final address = current.relocations
                .where(
                  (r) =>
                      r.section == function.section &&
                      r.offset >= function.offset &&
                      r.offset < end,
                )
                .map((r) => r.symbol)
                .toSet()
                .single;
            final symbol = current.symbols[address];
            expect(objects, contains(symbol));
            if (referenced[source] case final previous?) {
              expect(symbol, same(previous));
            } else {
              referenced[source] = symbol;
            }
          }
          for (final object in objects) {
            final section = current.sections[object.section];
            expect(section.kind, SectionKind.data);
            expect(object.offset % ObjectHeader.alignment, 0);
            final bytes = ByteData.sublistView(section.bytes);
            expect(
              bytes.getInt64(object.offset + ObjectHeader.sizeOffset, .little),
              80,
            );
            expect(
              bytes.getInt64(object.offset + ObjectHeader.pageOffset, .little),
              0,
            );
            expect(bytes.getInt64(object.offset + 40, .little), -73);
            expect(
              current.relocations
                  .where(
                    (r) =>
                        r.section == object.section &&
                        r.offset >= object.offset &&
                        r.offset < object.offset + 80,
                  )
                  .map((r) => r.offset - object.offset)
                  .toSet(),
              {0, 8, 48},
            );
          }
          final tableSymbol = current.symbols.singleWhere(
            (s) => s.name == '.dartc.moduleRoots',
          );
          final section = current.sections[tableSymbol.section];
          expect(section.kind, SectionKind.readOnlyData);
          expect(
            ByteData.sublistView(section.bytes)
                .getInt64(tableSymbol.offset + ModuleRootTable.count, .little),
            2,
          );
          final tableReferences = current.relocations.where(
            (r) =>
                r.section == tableSymbol.section &&
                r.offset >= tableSymbol.offset + ModuleRootTable.entries &&
                r.offset <
                    tableSymbol.offset +
                        ModuleRootTable.entries +
                        2 * ModuleRootTable.entrySize,
          );
          expect(
            tableReferences.map((r) => current.symbols[r.symbol]).toSet(),
            objects.toSet(),
          );
          expect(current.symbols.where((s) => s.name == 'unused'), isEmpty);
        }
      }
    }
  });
}
