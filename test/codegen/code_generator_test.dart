import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

import 'fixtures/aliases.dart';

void main() {
  setUpAll(prepareRuntime);
  test(
    'string construction includes its ordinary Dart List dependencies',
    () async {
      final lowered = await prepareRuntime(
        'test/compiler/fixtures/strings.dart',
      );
      final entry = lowered.program.functions
          .firstWhere((f) => f.target.name == 'stringCodesProtocol')
          .target;
      final definitions = lowered.program.reachableFrom([entry]).toSet();
      expect(
        lowered.program.functions
            .where((f) => definitions.contains(f.target))
            .expand((f) => f.blocks)
            .expand((b) => b.instructions)
            .whereType<NewCollection>(),
        isNotEmpty,
      );
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.macos, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        final module = generator.generate(
          lowered.program,
          runtime: heapRuntime,
          definitions: definitions,
        );
        expect(
          module.symbols.map((s) => s.name),
          containsAll(['fromCharCodes', 'empty', 'add']),
        );
      }
    },
  );

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
                program,
                runtime: heapRuntime,
                definitions: [function.target],
              )
              .symbols
              .map((s) => s.name),
          contains('length'),
        );
      }
    }
  });

  test(
    'List constants and construction select only required native bodies',
    () async {
      for (final (fixture, root, required) in [
        ('lists_overflow', 'main', 'filled'),
        ('lists', 'listConstantOnly', '[]'),
      ]) {
        final lowered = await prepareRuntime(
          'test/compiler/fixtures/$fixture.dart',
        );
        final entry = lowered.program.functions
            .firstWhere((body) => body.target.name == root)
            .target;
        for (final CodeGenerator generator in [
          Arm64CodeGenerator(const Target(.macos, .arm64)),
          X64CodeGenerator(const Target(.linux, .x64)),
        ]) {
          final module = generator.generate(
            lowered.program,
            runtime: heapRuntime,
            definitions: lowered.program.reachableFrom([entry]),
          );
          final names = module.symbols.map((symbol) => symbol.name);
          expect(names, contains(required));
          for (final name in ['addAll', 'sublist', 'iterator']) {
            expect(names, isNot(contains(name)), reason: name);
          }
        }
      }
    },
  );

  test('void store results remain readable as null', () {
    final target = FunctionTarget(
      .parse('memory:void-store'),
      'store',
      .voidType,
      [FfiTypes.resolve(NativePointerType(NativeScalarType(Int64)))],
    );
    final block = Block(target.parameterTypes);
    block.finish(
      Return(
        block.emit(
          StoreNative(
            block.emit(PointerAddress(block.parameters.single)),
            .of(Int64),
            const Constant.integer(42),
          ),
        ),
      ),
    );
    final program = IrProgram([], [
      IrFunction(target, [block]),
    ]);
    for (final CodeGenerator generator in [
      Arm64CodeGenerator(const Target(.macos, .arm64)),
      X64CodeGenerator(const Target(.linux, .x64)),
    ]) {
      expect(
        generator
            .generate(program, runtime: heapRuntime, definitions: [target])
            .sections,
        isNotEmpty,
      );
    }
  });

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
          program,
          runtime: heapRuntime,
          definitions: [target],
        );
        expect(module.relocations, isEmpty);
        expect(module.symbols.single.name, 'invoke');
        expect(module.sections.single.bytes, isNotEmpty);
      }
    }
  });

  test(
    'definition selection and native exports are separate checked inputs',
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
        expect(
          () => generator.generate(
            program,
            runtime: heapRuntime,
            definitions: [entry],
          ),
          throwsArgumentError,
        );
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
        expect(
          () => generator.generate(
            IrProgram([], [
              ...arithmeticProgram.functions,
              IrFunction(entry, [withSupport]),
            ]),
            runtime: heapRuntime,
            definitions: [entry],
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            runtime: heapRuntime,
            definitions: [callee],
            exports: {
              entry: NativeExport(
                'caller',
                NativeSignature(Int64, List.filled(0, Int64)),
              ),
            },
          ),
          throwsArgumentError,
        );
        expect(
          () => generator.generate(
            program,
            runtime: heapRuntime,
            definitions: [callee],
            exports: {
              callee: NativeExport(
                'add',
                NativeSignature(Int64, List.filled(0, Int64)),
              ),
            },
          ),
          throwsArgumentError,
        );
        final module = generator.generate(
          program,
          runtime: heapRuntime,
          definitions: [entry, callee],
        );
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
        program,
        runtime: heapRuntime,
        definitions: exports.keys,
        exports: exports,
      );
      final second = generator.generate(
        program,
        runtime: heapRuntime,
        definitions: exports.keys,
        exports: exports,
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
