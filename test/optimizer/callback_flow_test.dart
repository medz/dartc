import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('memory:callback-flow');
final _native = FunctionType(FfiTypes.int64, [FfiTypes.int64]);
final _consume = FunctionTarget(_uri, 'consume', .voidType, [.integer]);

void main() {
  for (final stored in [false, true]) {
    test(
      'native callback keeps optional defaults after raw exposure ($stored)',
      () {
        final function = FunctionTarget(_uri, 'callback', .integer, [
          .integer,
          .integer,
        ], optionalPositional: 1);
        final entryBody = Block(function.parameterTypes);
        entryBody.finish(Return(entryBody.parameters.last));
        final callback = IrFunction(
          function,
          [entryBody],
          defaults: {1: const Constant.integer(37)},
        );
        final declaration = StaticCallbackTarget(
          function,
          _native,
          exceptionalReturn: const Constant.integer(-1),
        );
        final entry = Block();
        final address = entry.emit(NativeCallbackAddress(declaration));
        final cloned = entry.emit(address.mapInputs((value) => value));
        final equal = entry.emit(Equals(address, cloned));
        final bytes = ClassType(_uri, 'Bytes');
        final layout = _Memory();
        Value exposed = address;
        if (stored) {
          final buffer = entry.emit(
            NewPayload(bytes, const Constant.integer(8)),
          );
          exposed = entry.emit(
            IntBinary(
              .add,
              entry.emit(ReferenceAddress(buffer)),
              Constant.integer(layout.objectLayout(bytes).size),
            ),
          );
          entry.emit(StoreNative(exposed, NativeScalarType(Int64), address));
        }
        entry.emit(DirectCall(_consume, [exposed]));
        entry.finish(Return(equal));
        final root = IrFunction(FunctionTarget(_uri, 'entry', .boolean, []), [
          entry,
        ]);
        final program = IrProgram(
          [IrClass(bytes, [])],
          [root, callback],
          externals: [IrExternal(_consume)],
        );
        final facts = ProgramFlow(program, [
          (target: root.target, arguments: []),
        ], memoryLayout: layout).facts;
        expect(
          facts.returnedBy(root.target).constant?.structuralKey,
          const Constant.boolean(true).structuralKey,
        );
        expect(
          facts.valueOf(entryBody.parameters.last).constant?.structuralKey,
          const Constant.integer(37).structuralKey,
        );
        expect(
          facts.returnedBy(function).constant?.structuralKey,
          const Constant.integer(37).structuralKey,
        );
        expect(facts.valueOf(address).addresses.single.base, same(declaration));
      },
    );
  }

  test(
    'trampoline lookup calls its closure with native arguments and defaults',
    () {
      final lookup = FunctionTarget(_uri, 'lookup', .function, [.integer]);
      final callback = FunctionTarget(
        _uri,
        'closure',
        .integer,
        [.integer, .integer],
        optionalPositional: 1,
        kind: .closure,
        enclosing: lookup,
        sourceOffset: 1,
        captures: [.integer],
      );
      final body = Block(callback.parameterTypes);
      body.finish(
        Return(
          body.emit(IntBinary(.add, body.parameters[1], body.parameters.last)),
        ),
      );
      final lookupBody = Block(lookup.parameterTypes);
      lookupBody.finish(
        Return(
          lookupBody.emit(MakeClosure(callback, [const Constant.integer(37)])),
        ),
      );
      final definition = ClosureCallbackTarget(
        lookup,
        callback.signature,
        _native,
        exceptionalReturn: const Constant.integer(-1),
      );
      final entry = Block();
      entry.emit(
        DirectCall(_consume, [entry.emit(NativeCallbackAddress(definition))]),
      );
      entry.finish(const Return());
      final root = IrFunction(FunctionTarget(_uri, 'entry', .voidType, []), [
        entry,
      ]);
      final program = IrProgram(
        [],
        [
          root,
          IrFunction(lookup, [lookupBody]),
          IrFunction(
            callback,
            [body],
            defaults: {1: const Constant.integer(11)},
          ),
        ],
        externals: [IrExternal(_consume)],
      );
      final facts = ProgramFlow(program, [
        (target: root.target, arguments: []),
      ]).facts;
      expect(
        facts.returnedBy(callback).constant?.structuralKey,
        const Constant.integer(48).structuralKey,
      );
      expect(
        facts.valueOf(body.parameters.last).constant?.structuralKey,
        const Constant.integer(11).structuralKey,
      );
    },
  );

  test('native exception fallback does not expose the thrown callable', () {
    final hidden = FunctionTarget(_uri, 'hidden', .integer, []);
    final hiddenBody = Block()..finish(const Return(Constant.integer(99)));
    final callback = FunctionTarget(_uri, 'throwing', .integer, [.integer]);
    final body = Block(callback.parameterTypes)
      ..finish(Throw(FunctionConstant(hidden)));
    final entry = Block();
    entry.emit(
      DirectCall(_consume, [
        entry.emit(
          NativeCallbackAddress(
            StaticCallbackTarget(
              callback,
              _native,
              exceptionalReturn: const Constant.integer(-1),
            ),
          ),
        ),
      ]),
    );
    entry.finish(const Return());
    final root = IrFunction(FunctionTarget(_uri, 'entry', .voidType, []), [
      entry,
    ]);
    final program = IrProgram(
      [],
      [
        root,
        IrFunction(callback, [body]),
        IrFunction(hidden, [hiddenBody]),
      ],
      externals: [IrExternal(_consume)],
    );
    final facts = ProgramFlow(program, [
      (target: root.target, arguments: []),
    ]).facts;
    expect(facts.definitions, contains(callback));
    expect(facts.definitions, isNot(contains(hidden)));
  });
}

final class _Memory() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .arm64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}
