import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
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
    test('${generator.target} stores canonical UTF-16 string constants', () {
      final texts = [
        '',
        'a',
        'a',
        'Dart 🐦',
        '\uD800x\uDC00',
        'Infinity or NaN toInt',
      ];
      final functions = [
        for (final (i, text) in texts.indexed)
          _returning(library, 'string$i', Constant.string(text), .string),
      ];
      final module = generator.generate(
        IrProgram([], functions),
        heapCapacity: heapCapacity,
        definitions: functions.map((f) => f.target),
      );
      final data = ByteData.sublistView(module.sections[1].bytes);
      expect(module.sections[1].kind, SectionKind.readOnlyData);
      final addresses = <int>[];
      for (final (i, function)
          in module.symbols.take(functions.length).indexed) {
        final references = module.relocations
            .whereType<InstructionRelocation>()
            .where(
              (r) =>
                  r.offset >= function.offset &&
                  r.offset < function.offset + function.size!,
            )
            .map((r) => r.symbol)
            .toSet();
        final address = references.single;
        addresses.add(address);
        final object = module.symbols[address];
        expect(
          data.getInt64(object.offset + ObjectLayout.fieldsOffset, .little),
          texts[i].length,
        );
        final units = object.offset + ObjectLayout.fieldsOffset + 8;
        expect(
          data.getInt64(object.offset + ObjectLayout.sizeOffset, .little),
          object.size,
        );
        expect(object.size, 40 + ((texts[i].length + 3) ~/ 4) * 8);
        expect([
          for (var j = 0; j < texts[i].length; j++)
            data.getUint16(units + j * 2, .little),
        ], texts[i].codeUnits);
        final descriptor =
            module.symbols[module.relocations
                .whereType<AddressRelocation>()
                .singleWhere((r) => r.offset == object.offset)
                .symbol];
        expect(data.getInt64(descriptor.offset, .little), 40);
        expect(data.getInt64(descriptor.offset + 8, .little), 1);
        expect(data.getInt64(descriptor.offset + 16, .little), 8);
      }
      expect(addresses[1], addresses[2]);
      expect(addresses.toSet(), hasLength(texts.length - 1));
    });

    test(
      '${generator.target} constructs using the receiver type environment',
      () {
        final parameter = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable)
          ..initializeDefaultType(.dynamicType);
        final generic = ClassType(
          library,
          'Generic',
          typeParameters: [parameter],
        );
        final ctor = FunctionTarget(
          library,
          '',
          .voidType,
          [],
          owner: generic,
          kind: .initializer,
        );
        final create = FunctionTarget(
          library,
          'create',
          generic,
          [],
          owner: generic,
          kind: .method,
        );
        final body = Block(create.parameterTypes);
        body.finish(Return(body.emit(Construct(ctor, []))));
        final program = IrProgram(
          [
            IrClass(generic, [], constructors: [ctor], members: [create]),
          ],
          [
            IrFunction(ctor, [
              Block(ctor.parameterTypes)..finish(const Return()),
            ]),
            IrFunction(create, [body]),
          ],
        );
        expect(
          generator
              .generate(
                program,
                heapCapacity: heapCapacity,
                definitions: [ctor, create],
              )
              .sections,
          isNotEmpty,
        );
      },
    );

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
        heapCapacity: heapCapacity,
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
      final descriptors = <int>[], runtimeTypes = <int>[];
      for (final (i, symbol) in addresses.indexed) {
        final object = module.symbols[symbol];
        final reference = module.relocations
            .whereType<AddressRelocation>()
            .singleWhere((r) => r.offset == object.offset);
        descriptors.add(reference.symbol);
        runtimeTypes.add(
          module.relocations
              .whereType<AddressRelocation>()
              .singleWhere((r) => r.offset == object.offset + 8)
              .symbol,
        );
        final descriptor = module.symbols[reference.symbol];
        expect(words.getInt64(descriptor.offset, .little), i < 4 ? 48 : 40);
        expect(words.getInt64(descriptor.offset + 8, .little), i < 4 ? 1 : 2);
        expect(words.getInt64(descriptor.offset + 16, .little), 8);
        if (i < 4) {
          expect(
            words.getInt64(object.offset + ObjectLayout.fieldsOffset, .little),
            7,
          );
          final floating = words.getFloat64(
            object.offset + ObjectLayout.fieldsOffset + 8,
            .little,
          );
          expect(
            1 / floating,
            i == 2 ? double.infinity : double.negativeInfinity,
          );
        } else {
          expect(
            words.getInt64(descriptor.offset + 24, .little),
            ObjectLayout.fieldsOffset,
          );
          expect(
            module.relocations
                .whereType<AddressRelocation>()
                .singleWhere(
                  (r) => r.offset == object.offset + ObjectLayout.fieldsOffset,
                )
                .symbol,
            addresses.first,
          );
        }
      }
      expect(descriptors[0], descriptors[2]);
      expect(descriptors.toSet(), hasLength(4));
      expect(runtimeTypes[0], runtimeTypes[2]);
      expect(runtimeTypes.toSet(), hasLength(4));
      expect(
        module.symbols.skip(functions.length).every((s) => s.binding == .local),
        isTrue,
      );
    });

    test(
      '${generator.target} requires storage and supports boxed generic fields',
      () {
        final missing = _returning(library, 'missing', first, base);
        expect(
          () => generator.generate(
            IrProgram([], [missing]),
            heapCapacity: heapCapacity,
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
                heapCapacity: heapCapacity,
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
                heapCapacity: heapCapacity,
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
