import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:closure-storage');
  IrFunction body(FunctionTarget target) => IrFunction(target, [
    Block(target.parameterTypes)..finish(const Return(Constant.integer(0))),
  ]);

  test(
    'static values share a carrier without allocation or wrapper bodies',
    () {
      final target = FunctionTarget(uri, 'plain', .integer, []);
      final first = FunctionConstant(target), second = FunctionConstant(target);
      final use = FunctionTarget(uri, 'use', first.type, []);
      final storage = ClosureStorage([
        body(target),
        IrFunction(use, [Block()..finish(Return(first))]),
        IrFunction(FunctionTarget(uri, 'again', second.type, []), [
          Block()..finish(Return(second)),
        ]),
      ]);
      expect(storage.constants, hasLength(1));
      expect(storage.constants[first.structuralKey]!.target, same(target));
      expect(storage.constants[first.structuralKey]!.initializer, isNull);
      expect(storage.functions, isEmpty);
      expect(
        () => ClosureStorage([
          IrFunction(use, [Block()..finish(Return(first))]),
        ]),
        throwsArgumentError,
      );
    },
  );

  test(
    'carriers retain capture order and outer lexical types, not own binders',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final u = TypeParameterType('U')
        ..initializeBound(ValueType.object.nullable);
      final v = TypeParameterType('V')
        ..initializeBound(ValueType.object.nullable);
      final owner = ClassType(uri, 'Owner', typeParameters: [t]);
      final outer = FunctionTarget(
        uri,
        'outer',
        .integer,
        [],
        kind: .method,
        owner: owner,
        typeParameters: [u],
      );
      final closure = FunctionTarget(
        uri,
        'inner',
        .integer,
        [],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 1,
        typeParameters: [v],
        captures: [CellType(.integer), t, .floating],
      );
      final storage = ClosureStorage([body(outer), body(closure)]);
      final shape = storage.closures[closure]!;
      expect(shape.parameters, [t, u]);
      expect(shape.captures.map((f) => f.type), [
        ValueType.object.nullable,
        ValueType.object.nullable,
        ValueType.floating,
      ]);
      expect(shape.initializer!.signature.parameters, [
        ValueType.integer,
        ValueType.object.nullable,
        ValueType.object.nullable,
        ValueType.floating,
        TypeValues.type,
        TypeValues.type,
      ]);
      final program = IrProgram([
        ...storage.classes,
        ...TypeValues().classes,
      ], storage.functions);
      expect(program.functions, hasLength(2));
      final layouts = ProgramLayout(program.classes);
      final fields = layouts.storageOf(shape.type);
      expect(fields.fields.first, same(storage.tag));
      expect(fields.layout.referenceOffsets, [8, 24, 32, 48, 56]);
      expect(storage.cell(CellType(.integer)).value.type, ValueType.integer);
    },
  );

  test(
    'cell shapes are collected from operations and stay fixed after layout',
    () {
      final target = FunctionTarget(uri, 'locals', .integer, []);
      final entry = Block();
      entry.emit(NewCell(CellType(.integer), const Constant.integer(1)));
      entry.emit(
        NewCell(CellType(.object.nullable), const Constant.nullValue()),
      );
      entry.emit(NewCell(CellType(.floating), const Constant.floating(1.5)));
      entry.finish(const Return(Constant.integer(0)));
      final storage = ClosureStorage([
        IrFunction(target, [entry]),
      ]);
      expect(storage.closures, isEmpty);
      expect(storage.classes, hasLength(3));
      expect(storage.cell(CellType(.floating)).value.type, ValueType.floating);
      expect(
        storage.cell(CellType(.object.nullable)).value.type,
        ValueType.object.nullable,
      );
      expect(
        storage.cell(CellType(.integer)),
        same(storage.cell(CellType(.integer))),
      );
      expect(() => storage.cell(CellType(.boolean)), throwsStateError);
      IrProgram(storage.classes, storage.functions);
    },
  );
}
