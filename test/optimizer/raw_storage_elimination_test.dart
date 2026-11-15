import 'dart:ffi' show Int64, Uint8;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:raw-storage-demand');
final _type = ClassType(_uri, 'Bytes');
final _declaration = IrClass(_type, []);
final _i64 = NativeScalarType(Int64);
final _u8 = NativeScalarType(Uint8);
const _zero = Constant.integer(0);
const _eight = Constant.integer(8);
const _answer = Constant.integer(42);

ProgramLayout _layout(IrProgram program) => ProgramLayout(
  program.classes,
  functions: program.functions,
  nativeLayout: NativeLayout(Target.host()),
);

int get _start =>
    _layout(IrProgram([_declaration], [])).objectLayout(_type).size;

Value _address(Block block, Value object, Value offset) =>
    block.emit(IntBinary(.add, block.emit(ReferenceAddress(object)), offset));

Iterable<Instruction> _operations(IrProgram program, FunctionTarget root) =>
    (program.implementationOf(root) as IrFunction).blocks.expand(
      (block) => [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    );

ProgramFlowFacts _analyze(
  IrProgram program,
  FunctionTarget root, [
  List<FlowValue>? arguments,
]) => ProgramFlow(program, [
  (
    target: root,
    arguments: arguments ?? root.parameterTypes.map(FlowValue.unknown).toList(),
  ),
], memoryLayout: _layout(program)).facts;

void main() {
  for (final origin in ['private', 'exposed', 'allocated']) {
    test('foreign reads retain only addressable object fields ($origin)', () {
      final field = InstanceField(_type, 'value', .integer);
      final declaration = IrClass(_type, [field]);
      final size = _layout(IrProgram([declaration], []))
          .objectLayout(_type)
          .size;
      final root = FunctionTarget(_uri, 'foreignRead', .integer, [
        .integer,
        .integer,
      ]);
      final block = Block(root.parameterTypes);
      final object = block.emit(
        origin == 'allocated'
            ? AllocatedObject(block.parameters.first, _type, _zero)
            : NewPayload(_type, _zero),
      );
      block.emit(StoreField(field, object, _answer));
      if (origin == 'exposed') block.emit(ReferenceAddress(object));
      block.emit(
        CopyNative(
          block.parameters.last,
          block.parameters.first,
          NativeArrayType(_u8, size),
        ),
      );
      block.finish(const Return(_answer));
      final program = IrProgram(
        [declaration],
        [
          IrFunction(root, [block]),
        ],
      );
      final after = const ProgramStorageElimination().run(
        _analyze(program, root),
      );
      expect(
        _operations(after, root).whereType<StoreField>(),
        origin == 'private' ? isEmpty : hasLength(1),
      );
      expect(_operations(after, root).whereType<CopyNative>(), hasLength(1));
    });
  }

  test('scalar outputs do not observe private object lifetimes', () {
    final field = InstanceField(_type, 'previous', _type.nullable);
    final source = InstanceField(_type, 'source', _type.nullable);
    final root = FunctionTarget(_uri, 'privateLink', .integer, [.integer]);
    final block = Block(root.parameterTypes);
    final object = block.emit(NewPayload(_type, _zero));
    final previous = block.emit(NewPayload(_type, _zero));
    block.emit(StoreField(source, object, previous));
    block.emit(StoreNative(block.parameters.single, _i64, _answer));
    final unknown = block.emit(LoadField(source, object));
    block.emit(StoreField(field, object, unknown));
    block.finish(Return(block.parameters.single));
    final program = IrProgram(
      [
        IrClass(_type, [field, source]),
      ],
      [
        IrFunction(root, [block]),
      ],
    );
    final facts =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramStorageElimination(),
        ]).run(program, [
          (target: root, arguments: [FlowValue.unknown(.integer)]),
        ], memoryLayoutFor: _layout);
    expect(_operations(facts.program, root).whereType<NewPayload>(), isEmpty);
    expect(
      _operations(facts.program, root).whereType<StoreNative>(),
      hasLength(1),
    );
  });

  for (final kind in ['native', 'object', 'copy']) {
    test(
      'private $kind writes disappear while their operand effects remain',
      () {
        final root = FunctionTarget(_uri, kind, .integer, [.integer]);
        final tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);
        final block = Block(root.parameterTypes);
        final object = block.emit(NewPayload(_type, _eight));
        final value = block.emit(DirectCall(tick, block.parameters));
        final offset = Constant.integer(_start);
        switch (kind) {
          case 'native':
            block.emit(
              StoreNative(_address(block, object, offset), _i64, value),
            );
          case 'object':
            block.emit(StoreObjectData(object, offset, _i64, value));
          case 'copy':
            final source = block.emit(NewPayload(_type, _eight));
            final address = _address(block, source, offset);
            block.emit(StoreNative(address, _i64, value));
            block.emit(
              CopyNative(_address(block, object, offset), address, _i64),
            );
        }
        block.finish(Return(block.parameters.single));
        final program = IrProgram(
          [_declaration],
          [
            IrFunction(root, [block]),
          ],
          externals: [
            IrExternal(tick, effects: {Effect.writesStorage}),
          ],
        );
        final facts =
            ProgramOptimizer(const [
              ProgramSimplification(),
              ProgramStorageElimination(),
            ]).run(program, [
              (target: root, arguments: [FlowValue.unknown(.integer)]),
            ], memoryLayoutFor: _layout);
        expect(
          _operations(facts.program, root).where(
            (op) =>
                op is NewPayload ||
                op is StoreNative ||
                op is StoreObjectData ||
                op is CopyNative,
          ),
          isEmpty,
        );
        for (final value in [-9, 0, 41]) {
          final events = <int>[];
          expect(
            IrInterpreter(facts.program, {
              (_uri, 'tick'): (int input) {
                events.add(input);
                return input;
              },
            }).run(facts.program.implementationOf(root) as IrFunction, [value]),
            value,
          );
          expect(events, [value]);
        }
      },
    );
  }

  for (final (name, offsets, removed) in [
    (
      'bounded',
      FlowValue.integerRange(FlowIntegerRange(_start, _start + 8)),
      true,
    ),
    ('header', FlowValue.constant(Constant.integer(_start - 1)), false),
    ('past end', FlowValue.constant(Constant.integer(_start + 9)), false),
    ('unknown', FlowValue.unknown(.integer), false),
  ]) {
    test('$name native write respects the complete access width', () {
      final root = FunctionTarget(_uri, 'write', .integer, [.integer]);
      final block = Block(root.parameterTypes);
      final object = block.emit(NewPayload(_type, const Constant.integer(16)));
      block.emit(
        StoreNative(
          _address(block, object, block.parameters.single),
          _i64,
          _answer,
        ),
      );
      block.finish(const Return(_answer));
      final program = IrProgram(
        [_declaration],
        [
          IrFunction(root, [block]),
        ],
      );
      final after = const ProgramStorageElimination().run(
        _analyze(program, root, [offsets]),
      );
      expect(
        _operations(after, root).whereType<StoreNative>(),
        removed ? isEmpty : hasLength(1),
      );
    });
  }

  for (final observation in [
    'native read',
    'object read',
    'external address',
  ]) {
    test('$observation retains aliased writes', () {
      final root = FunctionTarget(_uri, 'read', .integer, []);
      final block = Block();
      final object = block.emit(NewPayload(_type, _eight));
      final offset = Constant.integer(_start);
      final address = _address(block, object, offset);
      block.emit(StoreNative(address, _i64, _answer));
      final observer = FunctionTarget(_uri, 'observe', .voidType, [.integer]);
      final Value result;
      switch (observation) {
        case 'native read':
          result = block.emit(LoadNative(address, _i64));
        case 'object read':
          result = block.emit(LoadObjectData(object, offset, _i64));
        default:
          block.emit(DirectCall(observer, [address]));
          result = _answer;
      }
      block.finish(Return(result));
      final program = IrProgram(
        [_declaration],
        [
          IrFunction(root, [block]),
        ],
        externals: [
          IrExternal(observer, effects: {Effect.readsStorage}),
        ],
      );
      final after = const ProgramStorageElimination().run(
        _analyze(program, root),
      );
      expect(_operations(after, root).whereType<StoreNative>(), hasLength(1));
      expect(
        _analyze(after, root).returnedBy(root).constant?.structuralKey,
        _answer.structuralKey,
      );
    });
  }

  test(
    'copying from an unproved address remains even with an unused destination',
    () {
      final root = FunctionTarget(_uri, 'copy', .integer, [.integer]);
      final block = Block(root.parameterTypes);
      final object = block.emit(NewPayload(_type, _eight));
      block.emit(
        CopyNative(
          _address(block, object, Constant.integer(_start)),
          block.parameters.single,
          _i64,
        ),
      );
      block.finish(const Return(_answer));
      final program = IrProgram(
        [_declaration],
        [
          IrFunction(root, [block]),
        ],
      );
      final after = const ProgramStorageElimination().run(
        _analyze(program, root),
      );
      expect(_operations(after, root).whereType<CopyNative>(), hasLength(1));
    },
  );

  test('ordinary field reads retain raw initialization', () {
    final field = InstanceField(_type, 'value', .integer);
    final root = FunctionTarget(_uri, 'field', .integer, []);
    final program = IrProgram([
      IrClass(_type, [field]),
    ], []);
    final offset = _layout(program).objectLayout(_type).offsetOf(0);
    final entry = Block();
    final allocated = entry.emit(NewPayload(_type, _zero));
    entry.emit(StoreField(field, allocated, const Constant.integer(17)));
    entry.emit(
      StoreObjectData(allocated, Constant.integer(offset), _i64, _answer),
    );
    entry.finish(Return(entry.emit(LoadField(field, allocated))));
    final graph = IrProgram(program.classes, [
      IrFunction(root, [entry]),
    ]);
    final after = const ProgramStorageElimination().run(_analyze(graph, root));
    expect(_operations(after, root).whereType<StoreObjectData>(), hasLength(1));
    expect(
      _analyze(after, root).returnedBy(root).constant?.structuralKey,
      isNot(const Constant.integer(17).structuralKey),
    );
  });

  test('copied pointer contents retain weakly observed objects', () {
    final weakType = ClassType(_uri, 'Weak');
    final field = InstanceField(weakType, 'target', _type.nullable);
    final constructor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [_type],
      owner: weakType,
      kind: .initializer,
    );
    final initialize = Block(constructor.parameterTypes);
    initialize.emit(
      StoreField(field, initialize.parameters[0], initialize.parameters[1]),
    );
    initialize.finish(const Return());
    final root = FunctionTarget(_uri, 'weakCopy', .boolean, []);
    final collect = FunctionTarget(_uri, 'collect', .voidType, []);
    final block = Block();
    final target = block.emit(NewPayload(_type, _eight));
    final weak = block.emit(Construct(constructor, [target]));
    final source = block.emit(NewPayload(_type, _eight));
    final destination = block.emit(NewPayload(_type, _eight));
    final offset = Constant.integer(_start);
    final sourceAddress = _address(block, source, offset);
    block.emit(
      StoreNative(sourceAddress, _i64, block.emit(ReferenceAddress(target))),
    );
    block.emit(
      CopyNative(_address(block, destination, offset), sourceAddress, _i64),
    );
    block.emit(DirectCall(collect, []));
    final result = block.emit(
      TypeTest(block.emit(LoadField(field, weak)), _type),
    );
    block.emit(KeepAlive(destination));
    block.finish(Return(result));
    final program = IrProgram(
      [
        IrClass(_type, [], referencePayload: true),
        IrClass(
          weakType,
          [field],
          constructors: [constructor],
          weakFields: [field],
        ),
      ],
      [
        IrFunction(constructor, [initialize]),
        IrFunction(root, [block]),
      ],
      externals: [
        IrExternal(collect, effects: {Effect.allocates}),
      ],
    );
    final after = const ProgramStorageElimination().run(
      _analyze(program, root),
    );
    expect(_operations(after, root).whereType<CopyNative>(), hasLength(1));
    expect(_operations(after, root).whereType<StoreNative>(), hasLength(1));
    expect(_operations(after, root).whereType<KeepAlive>(), hasLength(1));
  });

  test('an observed raw address retains ordinary constructor fields', () {
    final field = InstanceField(_type, 'value', .integer);
    final constructor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [.integer],
      owner: _type,
      kind: .initializer,
    );
    final creating = Block(constructor.parameterTypes);
    creating.emit(
      StoreField(field, creating.parameters[0], creating.parameters[1]),
    );
    creating.finish(const Return());
    final root = FunctionTarget(_uri, 'readFieldBytes', .integer, []);
    final block = Block();
    final object = block.emit(Construct(constructor, [_answer]));
    block.finish(
      Return(
        block.emit(
          LoadNative(_address(block, object, Constant.integer(_start)), _u8),
        ),
      ),
    );
    final program = IrProgram(
      [
        IrClass(_type, [field], constructors: [constructor]),
      ],
      [
        IrFunction(constructor, [creating]),
        IrFunction(root, [block]),
      ],
    );
    final after = const ProgramStorageElimination().run(
      _analyze(program, root),
    );
    expect(
      _operations(after, constructor).whereType<StoreField>(),
      hasLength(1),
    );
  });
}
