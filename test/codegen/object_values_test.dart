import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('memory:constant-objects');
  final base = ClassType(library, 'Base');
  final child = ClassType(library, 'Child', superclass: base);
  final x = InstanceField(base, 'x', .integer, isFinal: true);
  final y = InstanceField(base, 'y', .floating, isFinal: true);
  final parameter = TypeParameterType('T')
    ..initializeBound(ValueType.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final box = ClassType(library, 'Box', typeParameters: [parameter]);
  final item = InstanceField(box, 'item', parameter, isFinal: true);
  final classes = [
    IrClass(base, [x, y]),
    IrClass(child, []),
    IrClass(box, [item]),
  ];
  final first = ObjectConstant(base, {
    x: const .integer(7),
    y: const .floating(-0.0),
  });

  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test('${generator.target} preserves constant and type identities', () {
      final values = [
        first,
        ObjectConstant(base, {y: const .floating(-0.0), x: const .integer(7)}),
        ObjectConstant(base, {x: const .integer(7), y: const .floating(0.0)}),
        ObjectConstant(child, first.fields),
        ObjectConstant(box.instantiate([base]), {item: first}),
        ObjectConstant(box.instantiate([ValueType.object]), {item: first}),
      ];
      final functions = [
        for (final (i, value) in values.indexed)
          _returning(library, 'constant$i', value, .object),
      ];
      final module = generator.generate(
        IrProgram(classes, functions),
        definitions: functions.map((f) => f.target),
      );
      final addresses = [
        for (final function in module.symbols.take(functions.length))
          module.relocations
              .whereType<InstructionRelocation>()
              .where(
                (r) =>
                    r.offset >= function.offset &&
                    r.offset < function.offset + function.size!,
              )
              .map((r) => r.symbol)
              .toSet()
              .single,
      ];
      expect(addresses[0], addresses[1]);
      expect(addresses.toSet(), hasLength(5));
      final data = module.sections[1];
      expect(data.kind, SectionKind.readOnlyData);
      final words = ByteData.sublistView(data.bytes);
      final descriptors = <int>[];
      for (final (i, symbol) in addresses.indexed) {
        final object = module.symbols[symbol];
        final reference = module.relocations
            .whereType<AddressRelocation>()
            .singleWhere((r) => r.offset == object.offset);
        descriptors.add(reference.symbol);
        final descriptor = module.symbols[reference.symbol];
        expect(words.getInt64(descriptor.offset, .little), i < 4 ? 24 : 16);
        expect(words.getInt64(descriptor.offset + 8, .little), i < 4 ? 0 : 1);
        if (i < 4) {
          expect(words.getInt64(object.offset + 8, .little), 7);
          final floating = words.getFloat64(object.offset + 16, .little);
          expect(
            1 / floating,
            i == 2 ? double.infinity : double.negativeInfinity,
          );
        } else {
          expect(words.getInt64(descriptor.offset + 16, .little), 8);
          expect(
            module.relocations
                .whereType<AddressRelocation>()
                .singleWhere((r) => r.offset == object.offset + 8)
                .symbol,
            addresses.first,
          );
        }
      }
      expect(descriptors[0], descriptors[2]);
      expect(descriptors.toSet(), hasLength(4));
      expect(
        module.symbols.skip(functions.length).every((s) => s.binding == .local),
        isTrue,
      );
    });

    test('${generator.target} rejects dynamic boxing at every transfer', () {
      final callee = FunctionTarget(library, 'accept', .object, [.object]);
      final targetBody = Block(callee.parameterTypes);
      targetBody.finish(Return(targetBody.parameters.single));
      final target = IrFunction(callee, [targetBody]);
      for (final operation in [
        'return',
        'call',
        'edge',
        'view',
        'initial',
        'write',
      ]) {
        final declaration = FunctionTarget(library, operation, .object, [
          .integer,
        ]);
        final body = Block(declaration.parameterTypes), join = Block([.object]);
        final value = body.parameters.single;
        final blocks = [body];
        Value result = value;
        switch (operation) {
          case 'call':
            result = body.emit(DirectCall(callee, [value]));
          case 'edge':
            body.finish(Jump(join, [value]));
            blocks.add(join);
            result = join.parameters.single;
          case 'view':
            result = body.emit(TypeView(value, .object));
          case 'initial' || 'write':
            final cell = body.emit(
              NewCell(CellType(.object), operation == 'initial' ? value : null),
            );
            if (operation == 'write') body.emit(WriteCell(cell, value));
            result = body.emit(ReadCell(cell));
        }
        blocks.last.finish(Return(result));
        final program = IrProgram([], [
          IrFunction(declaration, blocks),
          target,
        ]);
        expect(
          () => generator.generate(program, definitions: [declaration, callee]),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'reason',
              contains('representation conversion'),
            ),
          ),
          reason: operation,
        );
      }
    });

    test(
      '${generator.target} requires storage and supports boxed generic fields',
      () {
        final missing = _returning(library, 'missing', first, base);
        expect(
          () => generator.generate(
            IrProgram([], [missing]),
            definitions: [missing.target],
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'reason',
              contains('storage unavailable'),
            ),
          ),
        );
        final integers = box.instantiate([ValueType.integer]);
        final declaration = FunctionTarget(library, 'unbox', .integer, [
          integers,
        ]);
        final body = Block(declaration.parameterTypes);
        body.finish(Return(body.emit(LoadField(item, body.parameters.single))));
        expect(
          generator
              .generate(
                IrProgram(classes, [
                  IrFunction(declaration, [body]),
                ]),
                definitions: [declaration],
              )
              .sections
              .single
              .kind,
          SectionKind.code,
        );
        final boxedInteger = _returning(
          library,
          'boxed',
          ObjectConstant(integers, {item: const .integer(1)}),
          integers,
        );
        expect(
          generator
              .generate(
                IrProgram(classes, [boxedInteger]),
                definitions: [boxedInteger.target],
              )
              .sections
              .last
              .kind,
          SectionKind.readOnlyData,
        );
      },
    );
  }
}

IrFunction _returning(
  Uri library,
  String name,
  Constant value,
  ValueType type,
) {
  final declaration = FunctionTarget(library, name, type, []);
  return IrFunction(declaration, [Block()..finish(Return(value))]);
}
