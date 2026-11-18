import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final native = NativeCompoundType('Word', [NativeField('word', .of(Int64))]);
  final platform = const Target(.linux, .arm64);

  test(
    'public preparation preserves native-view identities across fresh owners',
    () {
      final type = ClassType(null, 'View', nativeType: native);
      final root = FunctionTarget(null, 'address', .integer, []);
      final block = Block();
      final view = block.emit(
        NativeView(type, address: const Constant.integer(128)),
      );
      block.finish(Return(block.emit(NativeAddress(view))));
      final source = IrProgram(
        [IrClass(type, [])],
        [
          IrFunction(root, [block]),
        ],
      );
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(platform),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        final compiler = Compiler(generator.target);
        final first = compiler.prepare(source, roots: [root]);
        final second = compiler.prepare(first.program, roots: [root]);
        expect(generator.generate(second).imports, isEmpty);
        final original = first.program.classes
            .singleWhere((c) => c.type == type)
            .nativeViewStorage!;
        final repeated = second.program.classes
            .singleWhere((c) => c.type == type)
            .nativeViewStorage!;
        expect(repeated.address, same(original.address));
        expect(repeated.owner, same(original.owner));
        expect(repeated.initializer, same(original.initializer));
        expect(
          IrInterpreter(
            second.program,
            {},
          ).run(second.program.implementationOf(root) as IrFunction, []),
          128,
        );
      }
    },
  );

  test('a fresh owner consumes retained constructors and arbitrary prefix names', () {
    final base = ClassType(null, 'Base', nativeType: native);
    final child = ClassType(
      null,
      'Child',
      superclass: base,
      nativeType: native,
    );
    final address = InstanceField(base, 'location', .integer, isFinal: true);
    final ownerField = InstanceField(
      base,
      'lifetime',
      .object.nullable,
      isFinal: true,
    );
    final weak = InstanceField(base, 'weak', .object.nullable);
    final key = InstanceField(base, 'key', .object.nullable);
    final value = InstanceField(base, 'value', .object.nullable);
    final initializer = FunctionTarget(
      null,
      'borrow',
      .voidType,
      [.integer, .object.nullable],
      owner: child,
      kind: .initializer,
    );
    final initialization = Block(initializer.parameterTypes);
    initialization.emit(
      StoreField(
        address,
        initialization.parameters[0],
        initialization.parameters[1],
      ),
    );
    initialization.emit(
      StoreField(
        ownerField,
        initialization.parameters[0],
        initialization.parameters[2],
      ),
    );
    initialization.finish(const Return());
    final originalBody = IrFunction(initializer, [initialization]);
    final reader = FunctionTarget(null, 'read', .integer, [child]);
    final read = Block(reader.parameterTypes);
    read.finish(Return(read.emit(NativeAddress(read.parameters.single))));
    final original = IrProgram(
      [
        // Deliberately put the child before the owner of the materialized prefix.
        IrClass(
          child,
          [],
          constructors: [initializer],
          nativeViewStorage: (
            address: address,
            owner: ownerField,
            initializer: initializer,
          ),
        ),
        IrClass(
          base,
          [address, ownerField, weak, key, value],
          weakFields: [weak],
          ephemerons: {key: value},
          nativeViewStorage: (
            address: address,
            owner: ownerField,
            initializer: null,
          ),
        ),
      ],
      [
        originalBody,
        IrFunction(reader, [read]),
      ],
    );
    final firstOwner = NativeViews(NativeLayout(platform));
    final lowered = NativeViewLowering(firstOwner).lower(original, [reader]);
    final root = FunctionTarget(null, 'createAndRead', .integer, [.integer]);
    final entry = Block(root.parameterTypes);
    final view = entry.emit(
      NativeView(child, address: entry.parameters.single),
    );
    entry.finish(Return(entry.emit(DirectCall(reader, [view]))));
    final expanded = IrProgram(lowered.classes, [
      ...lowered.functions,
      IrFunction(root, [entry]),
    ]);
    final fresh = NativeViews(NativeLayout(platform));
    final result = NativeViewLowering(fresh).lower(expanded, [root]);
    expect(fresh.view(child).address, same(address));
    expect(fresh.view(child).owner, same(ownerField));
    expect(fresh.view(child).initializer, same(initializer));
    expect(result.implementationOf(initializer), same(originalBody));
    expect(
      (result.implementationOf(root) as IrFunction).entry.instructions
          .whereType<Construct>()
          .single
          .initializer,
      same(initializer),
    );
    final interpreter = IrInterpreter(result, {});
    for (final location in [128, 512, -16]) {
      expect(
        interpreter.run(result.implementationOf(root) as IrFunction, [
          location,
        ]),
        location,
      );
    }
    final layout = ProgramLayout(
      result.classes,
      nativeLayout: NativeLayout(platform),
      nativeViews: NativeViews(NativeLayout(platform)),
    );
    expect(layout.storageOf(child).fields, [
      address,
      ownerField,
      weak,
      key,
      value,
    ]);
    expect(layout.storageOf(child).weakFields, {weak});
    expect(layout.storageOf(child).ephemerons, {key: value});
    final output = StringBuffer();
    result.writeTo(output);
    expect(
      output.toString(),
      contains(
        'native-view address <generated>::Base.location owner <generated>::Base.lifetime',
      ),
    );
    expect(
      NativeViewLowering(NativeViews(NativeLayout(platform)))
          .lower(result, [root, reader]),
      same(result),
    );

    // This public entry still executes a field read from its unknown receiver.
    final compiler = Compiler(platform);
    final prepared = compiler.prepare(result, roots: [reader]);
    final repeated = compiler.prepare(prepared.program, roots: [reader]);
    expect(
      (repeated.program.implementationOf(reader) as IrFunction).blocks
          .expand((b) => b.instructions)
          .whereType<LoadField>()
          .single
          .field,
      same(address),
    );
    expect(Arm64CodeGenerator(platform).generate(repeated).symbols, isNotEmpty);
  });

  test('new prefix fields do not replace equal-named source fields', () {
    final type = ClassType(null, 'Names', nativeType: native);
    final sourceField = InstanceField(type, '_nativeAddress', .integer);
    final views = NativeViews(NativeLayout(platform));
    views.register([
      IrClass(type, [sourceField]),
    ]);
    final prefix = views.view(type);
    expect(prefix.address, isNot(same(sourceField)));
    expect(prefix.address.name, isNot(sourceField.name));
    final program = views.normalize(
      IrProgram([
        IrClass(type, [sourceField]),
      ], []),
    );
    expect(program.classes.single.fields, contains(sourceField));
    final fresh = NativeViews(NativeLayout(platform))
      ..register(program.classes);
    expect(fresh.view(type).address, same(prefix.address));
  });

  test('native-view contracts reject untraced owners and rebound inherited prefixes', () {
    final base = ClassType(null, 'Base', nativeType: native);
    final child = ClassType(
      null,
      'Child',
      superclass: base,
      nativeType: native,
    );
    final address = InstanceField(base, 'a', .integer, isFinal: true);
    final owner = InstanceField(base, 'b', .object.nullable, isFinal: true);
    final storage = (address: address, owner: owner, initializer: null);
    expect(
      () => IrClass(
        base,
        [address, owner],
        weakFields: [owner],
        nativeViewStorage: storage,
      ),
      throwsArgumentError,
    );
    expect(
      () => IrClass(base, [address], nativeViewStorage: storage),
      throwsArgumentError,
    );
    final replacement = InstanceField(base, 'c', .integer, isFinal: true);
    final baseClass = IrClass(base, [
      address,
      owner,
      replacement,
    ], nativeViewStorage: storage);
    final childClass = IrClass(
      child,
      [],
      nativeViewStorage: (
        address: replacement,
        owner: owner,
        initializer: null,
      ),
    );
    expect(() => IrProgram([baseClass, childClass], []), throwsArgumentError);
    final foreignAddress = InstanceField(child, 'a', .integer, isFinal: true);
    final foreignOwner = InstanceField(
      child,
      'b',
      .object.nullable,
      isFinal: true,
    );
    expect(
      () => IrClass(
        child,
        [foreignAddress, foreignOwner],
        nativeViewStorage: (
          address: foreignAddress,
          owner: foreignOwner,
          initializer: null,
        ),
      ),
      throwsArgumentError,
    );
  });
}
