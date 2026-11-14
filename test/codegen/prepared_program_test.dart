import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  const target = Target(.linux, .arm64);
  final uri = Uri.parse('memory:preparation');
  final entry = FunctionTarget(uri, 'entry', .integer, []);
  final other = FunctionTarget(uri, 'other', .integer, []);
  final extra = ClassType(uri, 'Extra');
  final program = IrProgram(
    [IrClass(extra, [])],
    [
      for (final function in [entry, other])
        IrFunction(function, [
          Block()..finish(const Return(Constant.integer(7))),
        ]),
    ],
  );

  test('preparation rejects foreign graphs and facts missing entry roots', () {
    final preparation = ProgramPreparation(target, program, roots: [entry]);
    final foreign = IrProgram(program.classes, program.functions);
    expect(
      () => preparation.prepare(CallTypeFlow(foreign, [entry]).facts),
      throwsArgumentError,
    );
    expect(
      () => preparation.prepare(CallTypeFlow(program, [other]).facts),
      throwsArgumentError,
    );
  });

  test('same-size fact changes invalidate preparation and emission', () {
    final preparation = ProgramPreparation(target, program, roots: [entry]);
    final flow = CallTypeFlow(
      preparation.program,
      preparation.roots,
      instantiatedTypes: preparation.instantiatedTypes,
    );
    final facts = flow.facts;
    final definitions = facts.definitions;
    final prepared = preparation.prepare(facts) as PreparedProgram;
    expect(flow.extend(instantiatedTypes: [extra]), isTrue);
    expect(flow.facts.definitions, definitions);
    expect(() => preparation.prepare(facts), throwsStateError);
    expect(
      () => Arm64CodeGenerator(target).generate(prepared),
      throwsStateError,
    );
    final current = preparation.prepare(flow.facts) as PreparedProgram;
    expect(current.definitions, {entry});
    expect(
      Arm64CodeGenerator(target).generate(current).symbols.single.name,
      'entry',
    );
  });

  test('prepared bindings and definitions cannot be changed by callers', () {
    final exports = {
      entry: NativeExport('visible', NativeSignature(Int64, [])),
    };
    final prepared = Compiler(target).prepare(program, exports: exports);
    exports.clear();
    expect(() => prepared.definitions.clear(), throwsUnsupportedError);
    final generator = Arm64CodeGenerator(target);
    final first = generator.generate(prepared),
        second = generator.generate(prepared);
    expect(first.symbols.single.name, 'visible');
    expect(second.sections.single.bytes, first.sections.single.bytes);
    expect(
      () => X64CodeGenerator(const .new(.linux, .x64)).generate(prepared),
      throwsArgumentError,
    );
    expect(
      () => Arm64CodeGenerator(const .new(.macos, .arm64)).generate(prepared),
      throwsArgumentError,
    );
  });

  test('native addresses must be bound before emission', () {
    final reference = NativeReference(
      'fixture',
      'storage',
      NativeTypeRef.of(Int64),
    );
    final block = Block();
    block.finish(Return(block.emit(NativeSymbolAddress(reference))));
    final input = IrProgram([], [
      IrFunction(entry, [block]),
    ]);
    expect(
      () => Compiler(target).prepare(input, roots: [entry]),
      throwsArgumentError,
    );
    final symbols = {reference: 'native_storage'};
    final prepared = Compiler(target)
        .prepare(input, roots: [entry], nativeSymbols: symbols);
    symbols.clear();
    expect(Arm64CodeGenerator(target).generate(prepared).imports, [
      'native_storage',
    ]);
  });

  test('an eliminated callback does not require a persistent runtime', () {
    final start = Block(), live = Block(), dead = Block();
    start.finish(Branch(const Constant.boolean(true), Jump(live), Jump(dead)));
    live.finish(const Return(Constant.integer(7)));
    dead.finish(
      Return(
        dead.emit(
          NativeCallbackAddress(
            other,
            FunctionType(FfiTypes.scalarTypes[Int64]!, []),
            exceptionalReturn: const Constant.integer(-1),
          ),
        ),
      ),
    );
    final input = IrProgram([], [
      IrFunction(entry, [start, live, dead]),
      program.implementationOf(other)! as IrFunction,
    ]);
    final prepared = Compiler(target).prepare(input, roots: [entry]);
    final module = Arm64CodeGenerator(target).generate(prepared);
    expect(module.symbols.map((symbol) => symbol.name), contains('entry'));
    expect(module.imports, isEmpty);
  });
}
