import 'dart:ffi' show Int64, Uint8, Void;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

Iterable<Instruction> _ops(IrFunction f) sync* {
  for (final b in f.blocks) {
    yield* b.instructions;
    if (b.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  final target = Target.host();
  final u8 = NativeScalarType(Uint8);
  final word = NativeScalarType(Int64);
  for (final handedOut in [false, true]) {
    test(
      'public prepare preserves a sibling read only when its module page may be handed out ($handedOut)',
      () {
        final a = NativeData(List.filled(64, 21), alignment: 8),
            b = NativeData(List.filled(64, 97), alignment: 8);
        final getA = FunctionTarget(null, 'moduleData', .integer, []),
            getB = FunctionTarget(null, 'readByte', .integer, []);
        final aa = Block(), bb = Block();
        final address = aa.emit(NativeDataAddress(a));
        aa.finish(Return(handedOut ? address : const Constant.integer(0)));
        bb.finish(
          Return(bb.emit(LoadNative(bb.emit(NativeDataAddress(b)), u8))),
        );
        final p = IrProgram([], [
          IrFunction(getA, [aa]),
          IrFunction(getB, [bb]),
        ]);
        final sig = NativeSignature(Int64, []);
        final exports = {
          getA: NativeExport('module_data', sig),
          getB: NativeExport('read_byte', sig),
        };
        final boundary = NativeBoundaries(p, exports: exports);
        final facts = ProgramFlow(
          boundary.program,
          [],
          openEntries: boundary.roots,
          memoryLayout: ProgramLayout([], nativeLayout: NativeLayout(target)),
        ).facts;
        final v = facts.returnedBy(getB).integers;
        final prepared = Compiler(target).prepare(p, exports: exports);
        final source = prepared.program.implementationOf(getB) as IrFunction;
        final instructions = _ops(source).map((x) => x.runtimeType).toList();
        print(
          'public expose=$handedOut returned=$v exact=${v?.constant} optimized readByte=$instructions',
        );
        final CodeGenerator generator = target.architecture == .arm64
            ? Arm64CodeGenerator(target)
            : X64CodeGenerator(target);
        final object = generator.generate(prepared);
        final data = object.symbols
            .where((s) => s.name.startsWith('.dartc.data'))
            .toList();
        print(
          'native data symbols ${data.map((s) => [s.section, s.offset, s.size])}',
        );
        if (handedOut) {
          expect(data, hasLength(2));
          expect(data.first.section, data.last.section);
          expect((data.first.offset - data.last.offset).abs(), 64);
        }
        expect(v?.constant, handedOut ? isNull : 97);
        expect(
          _ops(source).whereType<LoadNative>(),
          handedOut ? isNotEmpty : isEmpty,
        );
      },
    );
  }
  for (final kind in [
    'arbitrary',
    'arbitrary-unknown-size',
    'narrow-release',
    'page-release',
    'unknown-size',
    'hidden-result',
  ]) {
    test('lowered imported $kind has only its declared footprint', () {
      final hidden = kind == 'hidden-result';
      final release = kind.contains('release') || kind == 'unknown-size';
      final unknownLength = kind.contains('unknown-size');
      final sizeArgument = release || unknownLength;
      final pair = NativeCompoundType('Word', [NativeField('value', word)]);
      final type = ClassType(null, 'Word', nativeType: pair);
      final foreign = FunctionTarget(null, 'host', hidden ? type : .voidType, [
        if (!hidden) .integer,
        if (sizeArgument) .integer,
      ]);
      final signature = NativeSignature.types(hidden ? pair : .of(Void), [
        if (!hidden) word,
        if (sizeArgument) word,
      ]);
      final memory = release
          ? const ExternalMemory.release(0, 1)
          : const ExternalMemory.arbitrary();
      final decl = IrExternal(
        foreign,
        effects: {Effect.writesStorage},
        capturesArguments: false,
        memory: memory,
      );
      final boundaries = NativeBoundaries(
        IrProgram([if (hidden) IrClass(type, [])], [], externals: [decl]),
        imports: {foreign: signature},
        leafImports: [foreign],
        roots: [foreign],
      );
      final raw = boundaries.program.externals.single, rawTarget = raw.target;
      expect(raw.memory is NativeResultMemory, hidden);
      if (hidden) {
        expect(
          (raw.memory as NativeResultMemory).arguments,
          isA<ArbitraryMemory>(),
        );
      }
      if (release) expect(raw.memory, isA<ReleasedMemory>());
      final a = NativeData(List.filled(64, 21), alignment: 8),
          b = NativeData(List.filled(64, 97), alignment: 8);
      final root = FunctionTarget(null, 'check', .integer, [
            if (unknownLength) .integer,
          ]),
          entry = Block(root.parameterTypes);
      final aa = entry.emit(NativeDataAddress(a)),
          bb = entry.emit(NativeDataAddress(b));
      final tail = entry.emit(IntBinary(.add, aa, const Constant.integer(8)));
      entry.emit(
        DirectCall(rawTarget, [
          aa,
          if (sizeArgument)
            unknownLength
                ? entry.parameters.single
                : Constant.integer(kind == 'page-release' ? 16384 : 64),
        ]),
      );
      final first = entry.emit(LoadNative(aa, u8)),
          last = entry.emit(LoadNative(tail, u8)),
          neighbor = entry.emit(LoadNative(bb, u8));
      entry.finish(Return(neighbor));
      final p = IrProgram(boundaries.program.classes, [
        ...boundaries.program.functions,
        IrFunction(root, [entry]),
      ], externals: boundaries.program.externals);
      final f = ProgramFlow(
        p,
        [
          (
            target: root,
            arguments: [if (unknownLength) FlowValue.unknown(.integer)],
          ),
        ],
        memoryLayout: ProgramLayout(
          p.classes,
          nativeLayout: NativeLayout(target),
        ),
      ).facts;
      int? n(Value v) => f.valueOf(v).integers?.constant;
      print(
        'source=$kind sourceArgs=${foreign.parameterTypes.length} rawArgs=${rawTarget.parameterTypes.length} memory=${raw.memory.runtimeType} first=${n(first)} tail=${n(last)} B=${n(neighbor)}',
      );
      expect(n(first), isNull);
      expect(n(last), hidden ? 21 : isNull);
      expect(
        n(neighbor),
        kind == 'page-release' || kind == 'unknown-size' ? isNull : 97,
      );
    });
  }
  for (final hidden in [false, true]) {
    for (final captures in [false, true]) {
      test(
        'a later host entry sees only retained source arguments (output=$hidden captures=$captures)',
        () {
          final pair = NativeCompoundType('Word', [NativeField('value', word)]);
          final type = ClassType(null, 'Word', nativeType: pair);
          final foreign = FunctionTarget(
            null,
            'host',
            hidden ? type : .voidType,
            [if (!hidden) .integer],
          );
          final source = IrProgram(
            [if (hidden) IrClass(type, [])],
            [],
            externals: [
              IrExternal(
                foreign,
                effects: {Effect.writesStorage},
                capturesArguments: captures,
              ),
            ],
          );
          final binding = NativeBoundaries(
            source,
            roots: [foreign],
            imports: {
              foreign: NativeSignature.types(hidden ? pair : .of(Void), [
                if (!hidden) word,
              ]),
            },
            leafImports: [foreign],
          );
          final raw = binding.program.externals.single;
          final a = NativeData(List.filled(64, 21), alignment: 8),
              b = NativeData(List.filled(64, 97), alignment: 8);
          final lend = FunctionTarget(null, 'lend', .integer, []),
              readB = FunctionTarget(null, 'readB', .integer, []);
          final one = Block(), two = Block();
          // This raw input is either a real source pointer or only ABI copy-out.
          one.emit(DirectCall(raw.target, [one.emit(NativeDataAddress(a))]));
          one.finish(const Return(Constant.integer(0)));
          two.finish(
            Return(two.emit(LoadNative(two.emit(NativeDataAddress(b)), u8))),
          );
          final p = IrProgram(binding.program.classes, [
            IrFunction(lend, [one]),
            IrFunction(readB, [two]),
          ], externals: binding.program.externals);
          final facts = ProgramFlow(
            p,
            [],
            openEntries: [lend, readB],
            memoryLayout: ProgramLayout(
              p.classes,
              nativeLayout: NativeLayout(target),
            ),
          ).facts;
          final value = facts.returnedBy(readB).integers?.constant;
          print(
            'later entry hidden=$hidden captures=$captures observed B=$value',
          );
          expect(value, !hidden && captures ? isNull : 97);
        },
      );
    }
  }
}
