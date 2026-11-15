import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  test('emitted descriptors preserve weak slots and scalar box extents', () {
    final type = ClassType(null, 'Edges');
    final fields = [
      for (var i = 0; i < 4; i++)
        InstanceField(type, 'edge$i', .object.nullable),
    ];
    final layouts = ProgramLayout([
      IrClass(
        type,
        fields,
        weakFields: [fields[0]],
        ephemerons: {fields[1]: fields[2]},
      ),
    ], nativeLayout: NativeLayout(const Target(.linux, .arm64)));
    final data = ConstantData(layouts, 0);
    final descriptor = data.typeAddress(type);
    final integer = data.typeAddress(ValueType.integer);
    final floating = data.typeAddress(ValueType.floating);
    final bytes = ByteData.sublistView(data.finish().bytes);
    List<int> words(int symbol) {
      final start = data.symbols[symbol].offset;
      final end = symbol + 1 < data.symbols.length
          ? data.symbols[symbol + 1].offset
          : bytes.lengthInBytes;
      return [
        for (var i = start; i < end; i += 8) bytes.getInt64(i, Endian.little),
      ];
    }

    expect(words(descriptor), [72, 2, 8, 64, 0, 0, 1, 1, 40, 48, 56]);
    expect(words(integer), [48, 1, 8, 0, 0, 0, 0]);
    expect(words(floating), [48, 1, 8, 0, 0, 0, 0]);
    expect(layouts.objectLayout(ValueType.integer).size, 48);
    expect(layouts.objectLayout(ValueType.floating).fields, [
      ValueRepresentation.floating,
    ]);
  });

  test('Type constants preserve canonical identity without merging distinct top types', () {
    final data = ConstantData(
      ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      ),
      0,
    );
    final types = <ValueType>[
      .integer,
      .dynamicType,
      .voidType,
      .object.nullable,
      .never,
      .nullType,
    ];
    final symbols = types
        .map((type) => data.addressOf(TypeConstant(type)))
        .toList();
    expect(symbols.toSet().length, types.length);
    for (final (i, type) in types.indexed) {
      expect(data.addressOf(TypeConstant(type)), symbols[i]);
    }
  });

  test('Type constants retain declaration identity for matching names', () {
    final uri = Uri.parse('memory:type-identities');
    final types = [for (var i = 0; i < 66; i++) ClassType(uri, 'SameName')];
    final data = ConstantData(
      ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      ),
      0,
    );
    expect(
      types.map((t) => data.addressOf(TypeConstant(t))).toSet(),
      hasLength(66),
    );
  });

  test('Type constants normalize bound variables before nullable unions', () {
    final t = TypeParameterType('T')..initializeBound(ValueType.never);
    final u = TypeParameterType('U')..initializeBound(ValueType.never);
    final data = ConstantData(
      ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      ),
      0,
    );
    final a = FunctionType(t.nullable, [t], typeParameters: [t]);
    final b = FunctionType(.nullType, [.never], typeParameters: [u]);
    expect(data.addressOf(TypeConstant(a)), data.addressOf(TypeConstant(b)));
  });

  test(
    'constant objects canonicalize normalized type arguments and Type fields',
    () {
      final t = TypeParameterType('T')..initializeBound(ValueType.never);
      final u = TypeParameterType('U')..initializeBound(ValueType.never);
      final a = FunctionType(t, [t], typeParameters: [t]);
      final b = FunctionType(.never, [.never], typeParameters: [u]);
      final p = TypeParameterType('P')
        ..initializeBound(ValueType.object.nullable);
      final box = ClassType(
        Uri.parse('memory:constant-types'),
        'Box',
        typeParameters: [p],
      );
      final field = InstanceField(box, 'type', .typeType, isFinal: true);
      final data = ConstantData(
        ProgramLayout([
          IrClass(box, [field]),
        ], nativeLayout: NativeLayout(const Target(.linux, .arm64))),
        0,
      );
      int address(ValueType type) => data.addressOf(
        ObjectConstant(box.instantiate([type]), {field: TypeConstant(type)}),
      );
      expect(address(a), address(b));
      expect(address(a), isNot(address(ValueType.integer)));
    },
  );

  test('inherited Error traces use ordinary declared reference storage', () {
    final uri = Uri.parse('memory:error-layout');
    final base = ClassType(uri, 'Base', superclass: ValueType.error);
    final child = ClassType(uri, 'Child', superclass: base);
    final implementation = ClassType(
      uri,
      'Implementation',
      interfaces: [ValueType.error],
    );
    final trace = InstanceField(
      ValueType.error,
      '_stackTrace',
      ValueType.stackTrace.nullable,
    );
    final number = InstanceField(base, 'number', .integer);
    final reference = InstanceField(
      child,
      'reference',
      ValueType.object.nullable,
    );
    final layouts = ProgramLayout([
      IrClass(ValueType.error, [trace]),
      IrClass(base, [number]),
      IrClass(child, [reference]),
      IrClass(implementation, []),
    ], nativeLayout: NativeLayout(const Target(.linux, .arm64)));
    final storage = layouts.storageOf(child);
    expect(layouts.storageOf(ValueType.error).fields, [trace]);
    expect(layouts.storageOf(base).fields, [trace, number]);
    expect(storage.fields, [trace, number, reference]);
    expect(layouts.fieldOffset(trace), ObjectHeader.fieldsOffset);
    expect(storage.layout.size, ObjectHeader.fieldsOffset + 24);
    expect(storage.layout.referenceOffsets, [
      ObjectHeader.typeOffset,
      ObjectHeader.fieldsOffset,
      ObjectHeader.fieldsOffset + 16,
    ]);
    expect(layouts.fieldOffset(number), ObjectHeader.fieldsOffset + 8);
    expect(layouts.fieldOffset(reference), ObjectHeader.fieldsOffset + 16);
    expect(layouts.storageOf(implementation).fields, isEmpty);
    expect(layouts.storageOf(implementation).layout.referenceOffsets, [8]);
    expect(
      () => ConstantData(
        layouts,
        0,
      ).addressOf(ObjectConstant(ValueType.error, {})),
      throwsArgumentError,
    );
  });
}
