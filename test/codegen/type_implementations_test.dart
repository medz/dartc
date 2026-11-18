import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  test(
    'expanded projections execute old descriptors and newly reached classes',
    () {
      final uri = Uri.parse('memory:incremental-type-implementations');
      TypeParameterType parameter(String name) =>
          TypeParameterType(name)..initializeBound(.object.nullable);
      final a = parameter('A'), b = parameter('B');
      final base = ClassType(uri, 'Base', typeParameters: [a, b]);
      final x = parameter('X'), y = parameter('Y');
      final first = ClassType(
        uri,
        'First',
        typeParameters: [x, y],
        superclass: base.instantiate([y, x]),
      );
      final second = ClassType(
        uri,
        'Second',
        superclass: base.instantiate([.integer, .boolean]),
      );
      final third = ClassType(
        uri,
        'Third',
        superclass: first.instantiate([.integer, .floating]),
      );
      final owner = TypeImplementations(
        runtime: heapRuntime.types,
        declarations: [first],
      );
      final values = owner.values, relations = owner.relations;
      final old = values.constant(first.instantiate([.integer, .boolean]));
      final oldShape = values.id(first), baseShape = values.id(base);
      final viewTarget = relations.viewOf(base);
      final argumentTarget = relations.argumentOf(base, 0);
      final projection = relations.projection;
      final before = owner.functions.toList();
      final beforeRevision = owner.revision;
      final declarations = [base, first, second, third];

      List<int> execute(ObjectConstant descriptor) {
        IrFunction read(String name, FunctionTarget target, {int? shape}) {
          final targetName = FunctionTarget(uri, name, .integer, []);
          final block = Block();
          final value = block.emit(
            NullCheck(
              block.emit(
                DirectCall(target, [
                  descriptor,
                  if (shape != null) Constant.integer(shape),
                ]),
              ),
            ),
          );
          block.finish(
            Return(block.emit(LoadField(TypeMetadata.shape, value))),
          );
          return IrFunction(targetName, [block]);
        }

        final roots = [
          read('projection', projection.target, shape: baseShape),
          read('view', viewTarget),
          read('argument', argumentTarget),
        ];
        final source = heapRuntime.program;
        final program = IrProgram(
          [
            ...source.classes,
            for (final declaration in declarations) IrClass(declaration, []),
          ],
          [...source.functions, ...owner.functions, ...roots],
          globals: source.globals,
          externals: source.externals.where(
            (body) => body.target != projection.target,
          ),
        );
        final interpreter = IrInterpreter(program, {});
        return [for (final root in roots) interpreter.run(root, []) as int];
      }

      expect(execute(old), [
        baseShape,
        baseShape,
        values.id(ValueType.boolean),
      ]);
      expect(owner.extend([second]), isTrue);
      expect(owner.revision, greaterThan(beforeRevision));
      expect(relations.projection.target, same(projection.target));
      expect(relations.projection, same(projection));
      expect(relations.viewOf(base), same(viewTarget));
      expect(relations.argumentOf(base, 0), same(argumentTarget));
      expect(
        owner.functions.singleWhere((body) => body.target == viewTarget),
        same(before.singleWhere((body) => body.target == viewTarget)),
      );
      expect(values.id(first), oldShape);
      expect(
        values.constant(first.instantiate([.integer, .boolean])).structuralKey,
        old.structuralKey,
      );
      expect(execute(old), [
        baseShape,
        baseShape,
        values.id(ValueType.boolean),
      ]);
      expect(execute(values.constant(second)), [
        baseShape,
        baseShape,
        values.id(ValueType.integer),
      ]);

      final secondRevision = owner.revision;
      expect(owner.extend([third]), isTrue);
      expect(owner.revision, greaterThan(secondRevision));
      expect(relations.projection.target, same(projection.target));
      expect(execute(old), [
        baseShape,
        baseShape,
        values.id(ValueType.boolean),
      ]);
      expect(execute(values.constant(second)), [
        baseShape,
        baseShape,
        values.id(ValueType.integer),
      ]);
      expect(execute(values.constant(third)), [
        baseShape,
        baseShape,
        values.id(ValueType.floating),
      ]);
      final closedRevision = owner.revision;
      final closed = relations.projection;
      expect(owner.extend([first, second, third]), isFalse);
      expect(owner.revision, closedRevision);
      expect(relations.projection, same(closed));
    },
  );

  test('shape and template additions invalidate one persistent owner', () {
    final owner = TypeImplementations(runtime: heapRuntime.types);
    final values = owner.values;
    final revision = owner.revision;
    final type = ClassType(Uri.parse('memory:type-shape'), 'Fresh');
    final descriptor = values.constant(type);
    expect(owner.revision, greaterThan(revision));
    final shapeRevision = owner.revision;
    expect(values.constant(type).structuralKey, descriptor.structuralKey);
    expect(owner.revision, shapeRevision);

    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final template = values.instantiate(ValueType.futureOr(t));
    expect(owner.revision, greaterThan(shapeRevision));
    final templateRevision = owner.revision;
    expect(
      values.instantiate(ValueType.futureOr(t)).target,
      same(template.target),
    );
    expect(owner.revision, templateRevision);
    expect(
      owner.functions.any((body) => body.target == template.target),
      isTrue,
    );
  });

  test(
    'record carrier is bound from the checked runtime and remains stable',
    () {
      final owner = TypeImplementations(runtime: heapRuntime.types);
      final original = owner.relations.projection;
      final record = heapRuntime.program.classes.singleWhere(
        (c) => c.recordStorage,
      );
      final revision = owner.revision;
      expect(owner.extend([], recordStorage: record.type), isFalse);
      expect(owner.revision, revision);
      expect(owner.relations.projection.target, same(original.target));
      expect(owner.relations.projection, same(original));
      expect(owner.extend([], recordStorage: record.type), isFalse);
      expect(
        () => owner.extend([], recordStorage: ClassType(null, 'OtherRecord')),
        throwsStateError,
      );
    },
  );

  test('projection executes nested binders and normalized type arguments', () {
    final uri = Uri.parse('memory:projection-binders');
    TypeParameterType parameter(String name) =>
        TypeParameterType(name)..initializeBound(.object.nullable);
    final a = parameter('A'), b = parameter('B');
    final base = ClassType(uri, 'Base', typeParameters: [a, b]);
    final t = parameter('T'), u = parameter('U');
    final child = ClassType(
      uri,
      'Child',
      typeParameters: [t],
      superclass: base.instantiate([
        ValueType.futureOr(t),
        FunctionType(t.nullable, [u], typeParameters: [u]),
      ]),
    );
    final owner = TypeImplementations(
      runtime: heapRuntime.types,
      declarations: [child],
    );
    final roots = <IrFunction>[];
    for (final argument in [
      ValueType.integer,
      ValueType.object,
      ValueType.never,
    ]) {
      final actual = child.instantiate([argument]);
      final expected = actual.asInstanceOf(base)!;
      for (final slot in [-1, 0, 1]) {
        final target = FunctionTarget(
          uri,
          'check${roots.length}',
          .boolean,
          [],
        );
        final entry = Block();
        final projected = entry.emit(
          DirectCall(owner.relations.projectorOf(child), [
            owner.values.constant(actual),
            Constant.integer(owner.values.id(base)),
            Constant.integer(slot),
          ]),
        );
        entry.finish(
          Return(
            entry.emit(
              DirectCall(owner.values.equality, [
                entry.emit(NullCheck(projected)),
                owner.values.constant(
                  slot < 0 ? expected : expected.typeArguments[slot],
                ),
              ]),
            ),
          ),
        );
        roots.add(IrFunction(target, [entry]));
      }
    }
    final program = _program(owner, roots, [base, child]);
    final interpreter = _interpreter(program, owner);
    for (final root in roots) {
      expect(interpreter.run(root, []), isTrue, reason: root.target.name);
    }
  });

  test('non-nominal projection and missing arguments return null', () {
    final owner = TypeImplementations(runtime: heapRuntime.types);
    final roots = <IrFunction>[];
    for (final actual in [
      ValueType.nullType,
      ValueType.integer.nullable,
      ValueType.futureOr(.integer),
      FunctionType(.integer, []),
    ]) {
      for (final slot in [-1, 0]) {
        final target = FunctionTarget(
          null,
          'missing${roots.length}',
          .boolean,
          [],
        );
        final entry = Block();
        final result = entry.emit(
          DirectCall(
            slot < 0
                ? owner.relations.projection.target
                : owner.values.entry(.typeArgument),
            [
              owner.values.constant(actual),
              Constant.integer(owner.values.id(ValueType.object)),
              if (slot >= 0) Constant.integer(slot),
            ],
          ),
        );
        entry.finish(
          Return(entry.emit(Equals(result, const Constant.nullValue()))),
        );
        roots.add(IrFunction(target, [entry]));
      }
    }
    final program = _program(owner, roots, []);
    final interpreter = _interpreter(program, owner);
    for (final root in roots) {
      expect(interpreter.run(root, []), isTrue, reason: root.target.name);
    }
  });
}

IrProgram _program(
  TypeImplementations owner,
  List<IrFunction> roots,
  List<ClassType> declarations,
) {
  final source = heapRuntime.program;
  owner.extend(source.classes.map((declaration) => declaration.type));
  return IrProgram(
    [...source.classes, for (final type in declarations) IrClass(type, [])],
    [...source.functions, ...owner.functions, ...roots],
    globals: source.globals,
    externals: source.externals,
  );
}

IrInterpreter _interpreter(IrProgram program, TypeImplementations owner) =>
    IrInterpreter(
      program,
      {},
      typeLayout: ProgramLayout(
        program.classes,
        functions: program.functions,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        typeImplementations: owner,
      ),
    );
