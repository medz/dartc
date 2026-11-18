import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  final target = const Target(.linux, .arm64);
  final nativeType = NativeCompoundType('Word', [
    NativeField('value', .of(Int64)),
  ]);

  test(
    'one prefix identity preserves inherited managed fields and GC rules',
    () {
      final base = ClassType(null, 'NativeBase', nativeType: nativeType);
      final child = ClassType(
        null,
        'NativeChild',
        superclass: base,
        nativeType: nativeType,
      );
      final strong = InstanceField(base, 'strong', .object.nullable);
      final weak = InstanceField(base, 'weak', .object.nullable);
      final key = InstanceField(base, 'key', .object.nullable);
      final value = InstanceField(base, 'value', .object.nullable);
      final extra = InstanceField(child, 'extra', .object.nullable);
      final getter = FunctionTarget(
        null,
        'meaning',
        .integer,
        [],
        owner: base,
        kind: .getter,
      );
      final original = FunctionTarget(
        null,
        '_nativeView',
        .voidType,
        [],
        owner: base,
        kind: .initializer,
      );
      final root = FunctionTarget(null, 'address', .integer, [.object]);
      final block = Block(root.parameterTypes);
      final object = block.emit(
        NativeView(
          child,
          address: const Constant.integer(128),
          owner: block.parameters.single,
        ),
      );
      final upcast = block.emit(TypeView(object, base));
      block.finish(Return(block.emit(NativeAddress(upcast))));
      final program = IrProgram(
        [
          IrClass(
            base,
            [strong, weak, key, value],
            members: [getter],
            constructors: [original],
            weakFields: [weak],
            ephemerons: {key: value},
          ),
          IrClass(child, [extra]),
        ],
        [
          IrFunction(root, [block]),
          IrFunction(getter, [
            Block(getter.parameterTypes)
              ..finish(const Return(Constant.integer(42))),
          ]),
          IrFunction(original, [
            Block(original.parameterTypes)..finish(const Return()),
          ]),
        ],
      );
      final owner = NativeViews(NativeLayout(target));
      final pass = NativeViewLowering(owner);
      final lowered = pass.lower(program, [root]);
      final baseView = owner.view(base), childView = owner.view(child);
      expect(childView.address, same(baseView.address));
      expect(childView.owner, same(baseView.owner));
      final classes = {for (final c in lowered.classes) c.type: c};
      expect(classes[base]!.members[getter.selector], same(getter));
      expect(classes[base]!.constructors['_nativeView'], same(original));
      expect(
        classes[base]!.constructors.values,
        contains(baseView.initializer),
      );
      expect(baseView.initializer.name, isNot('_nativeView'));
      final layout = ProgramLayout(
        lowered.classes,
        nativeLayout: NativeLayout(target),
        nativeViews: owner,
      );
      final storage = layout.storageOf(child);
      expect(storage.fields, [
        baseView.address,
        baseView.owner,
        strong,
        weak,
        key,
        value,
        extra,
      ]);
      expect(
        storage.layout.referenceOffsets,
        containsAll([
          layout.fieldOffset(baseView.owner),
          layout.fieldOffset(strong),
          layout.fieldOffset(extra),
        ]),
      );
      expect(
        storage.layout.referenceOffsets,
        isNot(contains(layout.fieldOffset(weak))),
      );
      expect(storage.weakFields, {weak});
      expect(storage.ephemerons, {key: value});
      expect(layout.fieldOffset(childView.address), NativeViews.addressOffset);
      final facts = ProgramFlow(
        lowered,
        [],
        openEntries: [root],
        memoryLayout: layout,
      ).facts;
      expect((facts.returnedBy(root).constant as ScalarConstant).value, 128);
      expect(pass.lower(lowered, facts.definitions), same(lowered));
      final next = ProgramLayout(
        lowered.classes,
        nativeLayout: NativeLayout(target),
        nativeViews: owner,
      );
      expect(next.storageOf(child).fields, storage.fields);
    },
  );

  test('canonical abstract Struct reads the concrete view prefix', () {
    final concrete = ClassType(
      null,
      'Packet',
      superclass: FfiTypes.struct,
      nativeType: nativeType,
    );
    final root = FunctionTarget(null, 'address', .integer, []);
    final block = Block();
    final created = block.emit(
      NativeView(concrete, address: const Constant.integer(256)),
    );
    block.finish(
      Return(
        block.emit(
          NativeAddress(block.emit(TypeView(created, FfiTypes.struct))),
        ),
      ),
    );
    final program = IrProgram(
      [
        IrClass(FfiTypes.compound, []),
        IrClass(FfiTypes.struct, []),
        IrClass(concrete, []),
      ],
      [
        IrFunction(root, [block]),
      ],
    );
    final owner = NativeViews(NativeLayout(target));
    final lowered = NativeViewLowering(owner).lower(program, [root]);
    expect(owner.view(concrete).address.owner, FfiTypes.compound);
    final layout = ProgramLayout(
      lowered.classes,
      nativeLayout: NativeLayout(target),
      nativeViews: owner,
    );
    final facts = ProgramFlow(lowered, [
      (target: root, arguments: []),
    ], memoryLayout: layout).facts;
    expect((facts.returnedBy(root).constant as ScalarConstant).value, 256);
    expect(
      layout
          .storageOf(concrete)
          .fields
          .where((field) => field == owner.view(concrete).address),
      hasLength(1),
    );
  });

  test('unsupported ordinary parents are not assigned hidden native slots', () {
    final parent = ClassType(null, 'Ordinary');
    final type = ClassType(
      null,
      'Hybrid',
      superclass: parent,
      nativeType: nativeType,
    );
    final owner = NativeViews(NativeLayout(target));
    owner.register([IrClass(parent, []), IrClass(type, [])]);
    expect(owner.prefixFields(parent), isEmpty);
    expect(() => owner.view(type), throwsUnsupportedError);
  });

  test('owned and copying views expose payload, initialization and owner retention', () {
    final type = ClassType(null, 'Owned', nativeType: nativeType);
    for (final copy in [false, true]) {
      final root = FunctionTarget(null, 'create', type, [.integer, .object]);
      final block = Block(root.parameterTypes);
      block.finish(
        Return(
          block.emit(
            NativeView(
              type,
              address: copy ? block.parameters.first : null,
              owner: block.parameters.last,
              copy: copy,
            ),
          ),
        ),
      );
      final owner = NativeViews(NativeLayout(target));
      final lowered = NativeViewLowering(owner).lower(
        IrProgram(
          [IrClass(type, [])],
          [
            IrFunction(root, [block]),
          ],
        ),
        [root],
      );
      final body =
          lowered.implementationOf(owner.owned(type, copy: copy)) as IrFunction;
      final payload = body.entry.instructions.whereType<NewPayload>().single;
      expect(payload.type, owner.buffer);
      final construct = body.entry.instructions.whereType<Construct>().single;
      expect(construct.inputs.last, same(payload));
      expect(
        ValueLiveness.source(body, calls: {construct}).acrossCalls[construct],
        contains(payload),
      );
      expect(
        body.entry.instructions.whereType<CopyNative>(),
        copy ? hasLength(1) : isEmpty,
      );
      expect(
        body.entry.instructions.whereType<KeepAlive>().map((op) => op.value),
        contains(body.entry.parameters.last),
      );
    }
  });

  test('native copy executes the actual runtime overlap algorithm through ordinary calls', () async {
    await prepareRuntime();
    final root = FunctionTarget(null, 'copy', .voidType, [.integer, .integer]);
    final block = Block(root.parameterTypes);
    block.emit(
      CopyNative(
        block.parameters[0],
        block.parameters[1],
        NativeArrayType(.of(Uint8), 6),
      ),
    );
    block.finish(const Return());
    final source = IrProgram(
      heapRuntime.program.classes,
      [
        ...heapRuntime.program.functions,
        IrFunction(root, [block]),
      ],
      globals: heapRuntime.program.globals,
      externals: heapRuntime.program.externals,
    );
    final owner = NativeViews(NativeLayout(target));
    final lowered = NativeViewLowering(
      owner,
      copyBytes: heapRuntime.copyBytes,
    ).lower(source, [root]);
    final body = lowered.implementationOf(root) as IrFunction;
    expect(body.callees, contains(heapRuntime.copyBytes));
    expect(
      body.blocks.expand((b) => b.instructions).whereType<CopyNative>(),
      isEmpty,
    );
    final library = DynamicLibrary.process();
    final allocate = library
        .lookupFunction<
          Pointer<Uint8> Function(Size),
          Pointer<Uint8> Function(int)
        >('malloc');
    final release = library
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('free');
    final memory = allocate(10);
    if (memory.address == 0) throw StateError('allocation failed');
    try {
      final interpreter = IrInterpreter(lowered, {});
      for (final (destination, source, expected) in [
        (2, 0, [0, 1, 0, 1, 2, 3, 4, 5, 8, 9]),
        (0, 2, [2, 3, 4, 5, 6, 7, 6, 7, 8, 9]),
        (1, 1, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
      ]) {
        for (var i = 0; i < 10; i++) {
          memory[i] = i;
        }
        interpreter.run(body, [
          memory.address + destination,
          memory.address + source,
        ]);
        expect(memory.asTypedList(10), expected);
      }
    } finally {
      release(memory);
    }
    for (final CodeGenerator generator in [
      Arm64CodeGenerator(target),
      X64CodeGenerator(const Target(.linux, .x64)),
    ]) {
      final prepared = Compiler(generator.target)
          .prepare(source, runtime: heapRuntime, roots: [root]);
      expect(generator.generate(prepared).imports, isEmpty);
    }
  });
}
