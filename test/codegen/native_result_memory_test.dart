import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final word = NativeScalarType(Int64);
  final pair = NativeCompoundType('Pair', [
    NativeField('first', word),
    NativeField('second', word),
  ]);
  final type = ClassType(null, 'Pair', nativeType: pair);
  test('prepare keeps source argument indices for aggregate imports', () {
    final foreign = FunctionTarget(null, 'pair', type, [
      .floating,
      .integer,
      .integer,
    ]);
    final root = FunctionTarget(null, 'root', .integer, []);
    final entry = Block()..finish(const Return(Constant.integer(1)));
    final prepared = Compiler(Target.host()).prepare(
      IrProgram(
        [IrClass(type, [])],
        [
          IrFunction(root, [entry]),
        ],
        externals: [
          IrExternal(
            foreign,
            effects: {Effect.writesStorage},
            memory: const .write(1, 2),
          ),
        ],
      ),
      roots: [root],
      imports: {
        foreign: NativeImport(
          'pair',
          NativeSignature.types(pair, [NativeScalarType(Double), word, word]),
        ),
      },
    );
    expect(prepared.definitions, contains(root));
  });
  for (final writesArgument in [false, true]) {
    test(
      'aggregate copy-out and source writes use distinct ranges ($writesArgument)',
      () {
        final foreign = FunctionTarget(null, 'pair', type, [
          .integer,
          .integer,
        ]);
        final sig = NativeSignature.types(pair, [word, word]);
        final storage = FunctionTarget(null, 'storage', .integer, []);
        final boundaries = NativeBoundaries(
          IrProgram(
            [IrClass(type, [])],
            [],
            externals: [
              IrExternal(
                foreign,
                effects: {if (writesArgument) Effect.writesStorage},
                memory: writesArgument
                    ? const .write(0, 1)
                    : const .unchanged(),
                capturesArguments: false,
                terminates: true,
              ),
              IrExternal(
                storage,
                effects: {},
                memory: const .unchanged(),
                capturesArguments: false,
                terminates: true,
              ),
            ],
          ),
          roots: [foreign],
          imports: {foreign: sig},
        );
        final root = FunctionTarget(null, 'consume', .integer, []);
        final entry = Block();
        final first = entry.emit(DirectCall(storage, []));
        Value offset(int n) =>
            entry.emit(IntBinary(.add, first, Constant.integer(n)));
        final second = offset(8), trailing = offset(16), source = offset(24);
        for (final (address, initial) in [
          (first, 11),
          (second, 22),
          (trailing, 33),
          (source, 44),
        ]) {
          entry.emit(StoreNative(address, word, Constant.integer(initial)));
        }
        entry.emit(
          DirectCall(boundaries.imports.keys.single, [
            first,
            source,
            const Constant.integer(8),
          ]),
        );
        LoadNative read(Value a) => entry.emit(LoadNative(a, word));
        final firstRead = read(first),
            secondRead = read(second),
            trailingRead = read(trailing),
            sourceRead = read(source);
        entry.finish(Return(sourceRead));
        final program = IrProgram(boundaries.program.classes, [
          ...boundaries.program.functions,
          IrFunction(root, [entry]),
        ], externals: boundaries.program.externals);
        final facts = ProgramFlow(
          program,
          [(target: root, arguments: <FlowValue>[])],
          initialMemory: {storage: List.filled(32, 0)},
          memoryLayout: ProgramLayout(
            program.classes,
            nativeLayout: NativeLayout(Target.host()),
          ),
        ).facts;
        int? constant(Value value) => facts.valueOf(value).integers?.constant;
        expect(constant(firstRead), isNull);
        expect(constant(secondRead), isNull);
        expect(constant(trailingRead), 33);
        expect(constant(sourceRead), writesArgument ? isNull : 44);
      },
    );
  }
}
