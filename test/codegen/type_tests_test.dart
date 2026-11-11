import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final library = Uri.parse('memory:type-tests');
  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test('${generator.target} boxes scalar refinements to open references', () {
      final parameter = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final target = FunctionTarget(
        library,
        'promote',
        .object.nullable,
        [.integer],
        typeParameters: [parameter],
      );
      final entry = Block(target.parameterTypes),
          yes = Block([parameter]),
          no = Block();
      final test = entry.emit(TypeTest(entry.parameters.single, parameter));
      entry.finish(Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)));
      yes.finish(Return(yes.parameters.single));
      no.finish(Return(const Constant.nullValue()));
      final program = IrProgram([], [
        IrFunction(target, [entry, yes, no]),
      ]);
      expect(
        generator
            .generate(
              program,
              heapCapacity: heapCapacity,
              definitions: [target],
            )
            .sections,
        isNotEmpty,
      );
    });
    test('${generator.target} selects reachable runtimeType overrides', () {
      final owner = ClassType(library, 'Override');
      final interface = ClassType(library, 'Interface');
      final child = ClassType(
        library,
        'Child',
        superclass: owner,
        interfaces: [interface],
      );
      final getter = FunctionTarget(
        library,
        'runtimeType',
        .typeType,
        [],
        owner: owner,
        kind: .getter,
      );
      final getterBody = Block(getter.parameterTypes)
        ..finish(Return(TypeConstant(.integer)));
      for (final (source, direct) in [
        (ValueType.object.nullable, false),
        (owner, false),
        (child, false),
        (interface, false),
        (ValueType.object.nullable, true),
      ]) {
        final target = FunctionTarget(library, 'readType', .typeType, [source]);
        final body = Block(target.parameterTypes);
        body.finish(
          Return(
            body.emit(
              ObjectRuntimeType(body.parameters.single, direct: direct),
            ),
          ),
        );
        final root = FunctionTarget(library, 'entry', .typeType, []);
        final entry = Block();
        entry.finish(
          Return(entry.emit(DirectCall(target, [ObjectConstant(child, {})]))),
        );
        final program = IrProgram(
          [
            IrClass(owner, [], members: [getter]),
            IrClass(interface, []),
            IrClass(child, []),
          ],
          [
            IrFunction(getter, [getterBody]),
            IrFunction(target, [body]),
            IrFunction(root, [entry]),
          ],
        );
        final definitions = program.reachableFrom([root]);
        expect(definitions, {root, target, if (!direct) getter});
        expect(
          generator
              .generate(
                program,
                heapCapacity: heapCapacity,
                definitions: definitions,
              )
              .sections,
          isNotEmpty,
        );
        if (!direct) {
          expect(
            () => generator.generate(
              program,
              heapCapacity: heapCapacity,
              definitions: [root, target],
            ),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'reason',
                contains('Missing member definition'),
              ),
            ),
          );
        }
      }
    });
    test('${generator.target} rejects missing built-in Type members', () {
      final custom = ClassType(
        library,
        'CustomType',
        interfaces: [ValueType.typeType],
      );
      FunctionTarget hash(ClassType owner, {bool abstract = false}) =>
          FunctionTarget(
            owner.library,
            'hashCode',
            .integer,
            [],
            owner: owner,
            kind: .getter,
            isAbstract: abstract,
          );
      final declaration = hash(ValueType.typeType, abstract: true);
      final override = hash(custom);
      final target = FunctionTarget(library, 'hashType', .integer, []);
      final entry = Block();
      entry.emit(TypeView(ObjectConstant(custom, {}), .typeType));
      entry.finish(
        Return(
          entry.emit(InstanceCall(declaration, TypeConstant(.integer), [])),
        ),
      );
      final program = IrProgram(
        [
          IrClass(ValueType.typeType, [], members: [declaration]),
          IrClass(custom, [], members: [override]),
        ],
        [
          IrFunction(target, [entry]),
          IrFunction(override, [
            Block(override.parameterTypes)
              ..finish(const Return(Constant.integer(7))),
          ]),
        ],
      );
      expect(
        () => generator.generate(
          program,
          heapCapacity: heapCapacity,
          definitions: program.reachableFrom([target]),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'missing built-in implementation',
            contains('built-in member unavailable: Type.hashCode'),
          ),
        ),
      );
    });
    test(
      '${generator.target} folds proved tests without loading the operand',
      () {
        for (final (operand, type, expected) in <(Constant, ValueType, bool)>[
          (const .integer(1), .integer, true),
          (const .string('unused'), .object, true),
          (const .nullValue(), .object, false),
          (const .integer(1), .nullType, false),
          (const .nullValue(), .nullType, true),
          (const .integer(1), .never, false),
          (const .integer(1), .floating, false),
          (const .floating(1), .boolean, false),
        ]) {
          for (final negated in [false, true]) {
            final target = FunctionTarget(library, 'test', .boolean, []);
            final body = Block();
            body.finish(
              Return(body.emit(TypeTest(operand, type, negated: negated))),
            );
            final constant = Block()
              ..finish(Return(Constant.boolean(expected != negated)));
            ObjectModule generate(Block block) => generator.generate(
              IrProgram([], [
                IrFunction(target, [block]),
              ]),
              heapCapacity: heapCapacity,
              definitions: [target],
            );
            expect(
              generate(body).sections.single.bytes,
              generate(constant).sections.single.bytes,
            );
          }
        }
      },
    );

    test(
      '${generator.target} preserves calls producing a statically tested value',
      () {
        final producer = FunctionTarget(library, 'produce', .integer, []);
        final produced = Block()..finish(Return(const Constant.integer(7)));
        final target = FunctionTarget(library, 'test', .boolean, []);
        final body = Block();
        body.finish(
          Return(
            body.emit(TypeTest(body.emit(DirectCall(producer, [])), .object)),
          ),
        );
        final module = generator.generate(
          IrProgram([], [
            IrFunction(producer, [produced]),
            IrFunction(target, [body]),
          ]),
          heapCapacity: heapCapacity,
          definitions: [producer, target],
        );
        final call = module.relocations
            .whereType<InstructionRelocation>()
            .single;
        expect(module.symbols[call.symbol].name, 'produce');
      },
    );

    test('${generator.target} selects concrete and receiver type tests', () {
      final parameter = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable)
        ..initializeDefaultType(.dynamicType);
      final base = ClassType(library, 'Base');
      final child = ClassType(library, 'Child', superclass: base);
      final box = ClassType(library, 'Box', typeParameters: [parameter]);
      for (final (source, tested) in <(ValueType, ValueType)>[
        (.object.nullable, .integer),
        (base, child),
        (
          box.instantiate([ValueType.number]),
          box.instantiate([ValueType.integer]),
        ),
        (.nullType, parameter),
        (.integer, parameter),
        (FfiTypes.pointerTypes[Pointer<Int64>]!, parameter),
      ]) {
        final target = FunctionTarget(
          library,
          'test',
          .boolean,
          [source],
          owner: box,
          kind: .method,
        );
        final body = Block(target.parameterTypes);
        body.finish(Return(body.emit(TypeTest(body.parameters[1], tested))));
        final program = IrProgram(
          [
            IrClass(base, []),
            IrClass(child, []),
            IrClass(box, [], members: [target]),
          ],
          [
            IrFunction(target, [body]),
          ],
        );
        expect(
          generator
              .generate(
                program,
                heapCapacity: heapCapacity,
                definitions: [target],
              )
              .sections,
          isNotEmpty,
        );
      }
    });

    test('${generator.target} casts using the receiver type environment', () {
      final parameter = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable)
        ..initializeDefaultType(.dynamicType);
      final owner = ClassType(library, 'Box', typeParameters: [parameter]);
      for (final (source, cast) in <(ValueType, ValueType?)>[
        (.object.nullable, parameter),
        (parameter, .integer),
        (parameter.nullable, null),
      ]) {
        final target = FunctionTarget(
          library,
          'cast',
          .object.nullable,
          [source],
          owner: owner,
          kind: .method,
        );
        final body = Block(target.parameterTypes);
        body.finish(
          Return(
            body.emit(
              cast == null
                  ? NullCheck(body.parameters[1])
                  : TypeCast(body.parameters[1], cast),
            ),
          ),
        );
        final program = IrProgram(
          [
            IrClass(owner, [], members: [target]),
          ],
          [
            IrFunction(target, [body]),
          ],
        );
        expect(
          generator
              .generate(
                program,
                heapCapacity: heapCapacity,
                definitions: [target],
              )
              .sections,
          isNotEmpty,
        );
      }
    });
  }
}
