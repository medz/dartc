import 'dart:ffi';

import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/object/elf.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

import 'fixtures/aliases.dart';

void main() {
  setUpAll(prepareRuntime);
  test('List length needs no unused SDK error or iterator declarations', () {
    for (final constant in [false, true]) {
      final entry = Block();
      final type = CoreTypes.listOf(.integer);
      final list = constant
          ? SequenceConstant(type, [const Constant.integer(7)])
          : entry.emit(NewCollection(type));
      entry.finish(Return(entry.emit(CollectionLength(list))));
      final function = IrFunction(
        FunctionTarget(
          .parse('memory:list-length'),
          'lengthOnly',
          .integer,
          [],
        ),
        [entry],
      );
      final program = IrProgram([], [function]);
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.macos, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        expect(
          generator
              .generate(
                Compiler(generator.target).prepare(
                  program,
                  runtime: heapRuntime,
                  roots: [function.target],
                ),
              )
              .symbols
              .map((s) => s.name),
          contains('length'),
        );
      }
    }
  });

  test(
    'unreferenced declarations do not expand List code or metadata',
    () async {
      final lowered = await prepareRuntime('test/compiler/fixtures/lists.dart');
      final entry = lowered.program.functions
          .firstWhere((body) => body.target.name == 'listConstantOnly')
          .target;
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.macos, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        final module = generator.generate(
          Compiler(generator.target)
              .prepare(lowered.program, runtime: heapRuntime, roots: [entry]),
        );
        final names = module.symbols.map((symbol) => symbol.name);
        expect(names, contains('[]'));
        final t = TypeParameterType('T')..initializeBound(.object.nullable);
        final unused = ClassType(
          Uri.parse('memory:unreachable'),
          'Unused',
          typeParameters: [t],
        );
        final member = FunctionTarget(
          unused.library,
          'addAll',
          .integer,
          [],
          owner: unused,
          kind: .method,
        );
        final expanded = IrProgram(
          [
            ...lowered.program.classes,
            IrClass(unused, [], members: [member]),
          ],
          [
            ...lowered.program.functions,
            IrFunction(member, [
              Block(member.parameterTypes)
                ..finish(const Return(Constant.integer(91))),
            ]),
          ],
          globals: lowered.program.globals,
          externals: lowered.program.externals,
        );
        final enlarged = generator.generate(
          Compiler(generator.target)
              .prepare(expanded, runtime: heapRuntime, roots: [entry]),
        );
        if (generator.target.operatingSystem == .macos) {
          expect(
            MachO(generator.target).encodeObject(enlarged),
            MachO(generator.target).encodeObject(module),
          );
        } else {
          expect(
            Elf(generator.target).encodeObject(enlarged),
            Elf(generator.target).encodeObject(module),
          );
        }
      }
    },
  );

  test('typed native calls require no symbol binding or relocation', () {
    final callback = FfiTypes.resolve(
      NativePointerType(NativeFunctionType(NativeSignature(Int8, [Int64]))),
    );
    final target = FunctionTarget(
      .parse('memory:indirect'),
      'invoke',
      .integer,
      [callback, .integer],
    );
    final block = Block(target.parameterTypes);
    block.finish(
      Return(
        block.emit(NativeCall(block.parameters[0], [block.parameters[1]])),
      ),
    );
    final program = IrProgram([], [
      IrFunction(target, [block]),
    ]);
    for (final os in OperatingSystem.values) {
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(Target(os, .arm64)),
        X64CodeGenerator(Target(os, .x64)),
      ]) {
        final module = generator.generate(
          Compiler(generator.target)
              .prepare(program, runtime: heapRuntime, roots: [target]),
        );
        expect(module.relocations, isEmpty);
        expect(module.symbols.single.name, 'invoke');
      }
    }
  });

  test(
    'roots discover their callees and exports validate native signatures',
    () {
      final arithmeticProgram = arithmetic();
      final callee = arithmeticProgram.functions.first.target;
      final entry = FunctionTarget(
        .parse('memory:caller'),
        'caller',
        .integer,
        [],
      );
      final block = Block([]);
      final result = block.emit(
        DirectCall(callee, [Constant.integer(19), Constant.integer(23)]),
      );
      block.emit(
        DirectCall(callee, [Constant.integer(1), Constant.integer(2)]),
      );
      block.finish(Return(result));
      final program = IrProgram([], [
        ...arithmeticProgram.functions,
        IrFunction(entry, [block]),
      ]);
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.linux, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        final prepared = Compiler(generator.target)
            .prepare(program, runtime: heapRuntime, roots: [entry]);
        expect(prepared.definitions, containsAll([entry, callee]));
        final withSupport = Block();
        withSupport.emit(
          NumericRoundToDouble(const Constant.floating(1.5), .round),
        );
        withSupport.finish(
          Return(
            withSupport.emit(
              DirectCall(callee, [
                const Constant.integer(1),
                const Constant.integer(2),
              ]),
            ),
          ),
        );
        final supported = Compiler(generator.target).prepare(
          IrProgram([], [
            ...arithmeticProgram.functions,
            IrFunction(entry, [withSupport]),
          ]),
          runtime: heapRuntime,
          roots: [entry],
        );
        expect(supported.definitions, containsAll([entry, callee]));
        expect(generator.generate(supported).sections, isNotEmpty);
        final exported = generator.generate(
          Compiler(generator.target).prepare(
            program,
            runtime: heapRuntime,
            exports: {
              entry: NativeExport('caller', NativeSignature(Int64, [])),
            },
          ),
        );
        expect(
          exported.symbols.where((symbol) => symbol.exported).single.name,
          'caller',
        );
        expect(
          () => generator.generate(
            Compiler(generator.target).prepare(
              program,
              runtime: heapRuntime,
              roots: [callee],
              exports: {
                callee: NativeExport(
                  'add',
                  NativeSignature(Int64, List.filled(0, Int64)),
                ),
              },
            ),
          ),
          throwsArgumentError,
        );
        final module = generator.generate(prepared);
        expect(
          module.symbols.every(
            (symbol) => symbol.binding == .local && !symbol.exported,
          ),
          isTrue,
        );
        expect(module.relocations.map((r) => r.symbol), [1, 1]);
      }
    },
  );

  test('backends reject incompatible targets', () {
    expect(
      () => Arm64CodeGenerator(const .new(.linux, .x64)),
      throwsArgumentError,
    );
    expect(
      () => X64CodeGenerator(const .new(.macos, .arm64)),
      throwsArgumentError,
    );
  });

  test('one backend can generate independent modules repeatedly', () {
    final program = arithmetic();
    final exports = {
      for (final f in program.functions)
        f.target: NativeExport(
          f.target.name,
          NativeSignature(Int64, List.filled(2, Int64)),
        ),
    };
    for (final CodeGenerator generator in [
      Arm64CodeGenerator(const Target(.linux, .arm64)),
      X64CodeGenerator(const Target(.linux, .x64)),
    ]) {
      final first = generator.generate(
        Compiler(generator.target).prepare(
          program,
          runtime: heapRuntime,
          roots: exports.keys,
          exports: exports,
        ),
      );
      final second = generator.generate(
        Compiler(generator.target).prepare(
          program,
          runtime: heapRuntime,
          roots: exports.keys,
          exports: exports,
        ),
      );
      expect(second.sections.single.bytes, first.sections.single.bytes);
      expect(second.target, generator.target);
      expect(
        second.symbols.map((s) => s.name),
        exports.values.map((e) => e.symbol),
      );
    }
  });
}
