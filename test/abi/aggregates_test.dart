import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final real = NativeScalarType(Double), integer = NativeScalarType(Int32);
  final point = NativeCompoundType('Point', [
    NativeField('x', real),
    NativeField('y', real),
  ]);
  final mixed = NativeCompoundType('Mixed', [
    NativeField('index', integer),
    NativeField('value', real),
  ]);
  final large = NativeCompoundType('Large', [
    NativeField('values', NativeArrayType(integer, 7)),
  ]);
  final packed = NativeCompoundType('Packed', [
    NativeField('tag', NativeScalarType(Uint8)),
    NativeField('value', real),
  ], packing: 1);

  test(
    'native layouts reject arithmetic overflow before producing offsets',
    () {
      const maximum = 0x7fffffffffffffff;
      final byte = NativeScalarType(Uint8);
      final hugeBytes = NativeArrayType(byte, maximum);
      final empty = NativeCompoundType('Empty', [
        NativeField('tail', NativeArrayType(real, 0, variableLength: true)),
      ]);
      final invalid = [
        NativeArrayType(real, 1 << 60),
        NativeArrayType(real, (1 << 61) + 1),
        NativeArrayType(NativeArrayType(real, 1 << 30), 1 << 30),
        NativeCompoundType('Addition', [
          NativeField('a', hugeBytes),
          NativeField('b', byte),
        ]),
        NativeCompoundType('Alignment', [
          NativeField('a', hugeBytes),
          NativeField('b', real),
        ]),
        NativeCompoundType('TailPadding', [
          NativeField('a', real),
          NativeField('b', hugeBytes),
        ], isUnion: true),
      ];
      for (final os in OperatingSystem.values) {
        for (final architecture in Architecture.values) {
          final layout = NativeLayout(Target(os, architecture));
          expect(layout.of(hugeBytes).size, maximum);
          expect(
            layout.of(NativeArrayType(real, maximum ~/ 8)).size,
            maximum - 7,
          );
          for (final type in invalid) {
            expect(() => layout.of(type), throwsRangeError);
            expect(() => layout.leaves(type).first, throwsRangeError);
            expect(() => layout.homogeneous(type), throwsRangeError);
          }
          expect(layout.leaves(byte, maximum - 1).single.offset, maximum - 1);
          expect(() => layout.leaves(byte, maximum).first, throwsRangeError);
          expect(() => layout.leaves(byte, -1).first, throwsRangeError);
          expect(layout.leaves(NativeArrayType(empty, maximum)), isEmpty);
        }
      }
    },
  );

  test('variable array dimensions contribute only their declared minimum', () {
    final empty = NativeArrayType(real, 0, variableLength: true);
    final initial = NativeArrayType(real, 1, variableLength: true);
    final rows = NativeArrayType(
      NativeArrayType(real, 2),
      0,
      variableLength: true,
    );
    for (final array in [empty, initial, rows]) {
      final value = NativeCompoundType('Samples', [
        NativeField('tag', NativeScalarType(Uint8)),
        NativeField('values', array),
      ]);
      for (final target in [
        const Target(.macos, .arm64),
        const Target(.linux, .arm64),
        const Target(.linux, .x64),
      ]) {
        final storage = NativeLayout(target).of(value);
        expect(storage.offsets, [0, 8]);
        expect(storage.alignment, 8);
        expect(storage.size, array == initial ? 16 : 8);
      }
      expect(
        () => NativeCompoundType('Invalid', [
          NativeField('values', array),
          NativeField('tag', integer),
        ]),
        throwsArgumentError,
      );
    }
    expect(rows.declaration('rows'), 'double rows[][2]');
    expect(initial.declaration('values'), 'double values[1]');
    expect(initial, isNot(NativeArrayType(real, 1)));
    expect(() => NativeArrayType(real, 0), throwsArgumentError);
    expect(
      () => NativeArrayType(real, -1, variableLength: true),
      throwsArgumentError,
    );
    expect(() => NativeArrayType(empty, 2), throwsArgumentError);
  });

  test('native storage retains nested arrays, unions, packing and recursive pointers', () {
    for (final target in [
      const Target(.macos, .arm64),
      const Target(.linux, .arm64),
      const Target(.linux, .x64),
    ]) {
      final layout = NativeLayout(target);
      expect(layout.of(mixed).offsets, [0, 8]);
      expect((layout.of(mixed).size, layout.of(mixed).alignment), (16, 8));
      expect((layout.of(packed).size, layout.of(packed).alignment), (9, 1));
      final union = NativeCompoundType('Choice', [
        NativeField('point', point),
        NativeField('items', NativeArrayType(integer, 3)),
      ], isUnion: true);
      expect(layout.of(union).offsets, [0, 0]);
      expect(layout.of(union).size, 16);
      final node = NativeCompoundType.declare('Node');
      node.define([
        NativeField('next', NativePointerType(node)),
        NativeField('value', real),
      ]);
      expect(layout.of(node).size, 16);
      final invalid = NativeCompoundType.declare('Cycle');
      invalid.define([NativeField('self', invalid)]);
      expect(() => layout.of(invalid), throwsArgumentError);
      expect(() => node.define([]), throwsStateError);
    }
  });

  test('AAPCS64 separates homogeneous floats, word aggregates and indirect results', () {
    for (final os in [OperatingSystem.macos, OperatingSystem.linux]) {
      final abi = Arm64Abi(Target(os, .arm64));
      final flexible = NativeCompoundType('Samples', [
        NativeField('bias', real),
        NativeField('values', NativeArrayType(real, 0, variableLength: true)),
      ]);
      final prefix = abi.classify(NativeSignature.types(flexible, [flexible]));
      for (final location in [prefix.result, prefix.parameters.single]) {
        expect(
          (location as RegisterAggregate).parts.map((part) => part.register),
          [arm.Register.x0],
        );
      }
      final call = abi.classify(
        NativeSignature.types(point, [mixed, point, large]),
      );
      expect((call.result as RegisterAggregate).parts.map((p) => p.register), [
        arm.FloatRegister.d0,
        arm.FloatRegister.d1,
      ]);
      expect(
        (call.parameters[0] as RegisterAggregate).parts.map((p) => p.register),
        [arm.Register.x0, arm.Register.x1],
      );
      expect(
        (call.parameters[1] as RegisterAggregate).parts.map((p) => p.register),
        [arm.FloatRegister.d0, arm.FloatRegister.d1],
      );
      expect(
        (call.parameters[2] as IndirectArgument).pointer,
        isA<RegisterArgument>().having(
          (p) => p.register,
          'register',
          arm.Register.x2,
        ),
      );
      expect(
        (abi.classify(NativeSignature.types(large, [])).result
                as IndirectArgument)
            .pointer,
        isA<RegisterArgument>().having(
          (p) => p.register,
          'result address',
          arm.Register.x8,
        ),
      );
      final spill = abi.classify(
        NativeSignature.types(real, [...List.filled(7, real), point, real]),
      );
      expect(
        spill.parameters[7],
        isA<StackArgument>().having((p) => p.size, 'whole HFA', 16),
      );
      expect(
        spill.parameters.last,
        isA<StackArgument>().having((p) => p.offset, 'later float', 16),
      );
    }
  });

  test(
    'SysV classifies each eightbyte and rolls back an exhausted aggregate bank',
    () {
      final abi = X64Abi(const Target(.linux, .x64));
      final call = abi.classify(NativeSignature.types(mixed, [mixed]));
      expect((call.result as RegisterAggregate).parts.map((p) => p.register), [
        x64.Register.rax,
        x64.FloatRegister.xmm0,
      ]);
      expect(
        (call.parameters.single as RegisterAggregate).parts.map(
          (p) => p.register,
        ),
        [x64.Register.rdi, x64.FloatRegister.xmm0],
      );
      final spill = abi.classify(
        NativeSignature.types(large, [...List.filled(5, integer), mixed, real]),
      );
      expect(
        spill.result,
        isA<IndirectArgument>().having(
          (p) => p.returnedAddress,
          'echo address',
          x64.Register.rax,
        ),
      );
      expect(spill.parameters[5], isA<StackArgument>());
      expect(
        spill.parameters.last,
        isA<RegisterArgument>().having(
          (p) => p.register,
          'SSE bank remains available',
          x64.FloatRegister.xmm0,
        ),
      );
      expect(
        abi.classify(NativeSignature.types(packed, [packed])).result,
        isA<IndirectArgument>(),
      );
      final union = NativeCompoundType('Choice', [
        NativeField('value', real),
        NativeField('bits', NativeScalarType(Int64)),
      ], isUnion: true);
      expect(
        (abi.classify(NativeSignature.types(union, [])).result
                as RegisterAggregate)
            .parts
            .single
            .register,
        x64.Register.rax,
      );
    },
  );

  test('headers define referenced types once in dependency order', () {
    final node = NativeCompoundType.declare('Node');
    node.define([
      NativeField('next', NativePointerType(node)),
      NativeField('payload', mixed),
    ]);
    final out = StringBuffer();
    NativeExports([
      NativeExport(
        'readNode',
        NativeSignature.types(mixed, [
          NativePointerType(node),
          NativePointerType(NativeOpaqueType('Context')),
        ]),
      ),
    ]).writeHeader(out);
    final text = out.toString();
    expect(text, contains('struct Node* next;'));
    expect(text, contains('struct Mixed payload;'));
    expect(
      text.indexOf('struct Mixed {'),
      lessThan(text.indexOf('struct Node {')),
    );
    expect(
      text,
      contains('struct Mixed readNode(struct Node*, struct Context*);'),
    );
    expect(
      () => NativeCompoundType('', [NativeField('x', integer)]),
      throwsArgumentError,
    );
    for (final name in ['struct', 'a; int injected', '_Reserved', 'uint8_t']) {
      final declaration = NativeCompoundType(name, [NativeField('x', integer)]);
      expect(NativeLayout(const Target(.linux, .x64)).of(declaration).size, 4);
      final header = StringBuffer();
      NativeExports([
        NativeExport('value', NativeSignature.types(declaration, [])),
      ]).writeHeader(header);
      expect(header.toString(), contains('struct dartc_type_1 value(void);'));
      expect(header.toString(), isNot(contains('struct $name {')));
    }
  });

  test(
    'call contracts reject aliased hidden results and truncated addresses',
    () {
      expect(
        () => CallLayout(
          [const RegisterArgument(0)],
          IndirectArgument(const RegisterArgument(0)),
          [0],
        ),
        throwsArgumentError,
      );
      expect(
        () => IndirectArgument(StackArgument<int>(0, size: 4)),
        throwsArgumentError,
      );
    },
  );
}
