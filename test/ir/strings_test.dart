import 'package:dartc/ir.dart';

import 'dart:ffi' show Uint16;

import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('strings implement Pattern without making every Pattern a string', () {
    expect(ValueType.pattern.accepts(.string), isTrue);
    expect(ValueType.string.accepts(.pattern), isFalse);
    final join = Block([.pattern]);
    expect(
      Jump(join, [const Constant.string('a')]).arguments.single.type,
      ValueType.string,
    );
  });

  test('character ranges preserve UTF-16 values and reject invalid codes', () {
    final target = FunctionTarget(
      Uri.parse('memory:characters'),
      'build',
      .string,
      [CoreTypes.iterableOf(.integer), .integer, ValueType.integer.nullable],
    );
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          StringFromCharCodes(
            entry.parameters[0],
            entry.parameters[1],
            entry.parameters[2],
          ),
        ),
      ),
    );
    final function = IrFunction(target, [entry]);
    final runner = IrInterpreter(IrProgram([], [function]), {});
    for (final (codes, start, end, expected)
        in <(List<int>, int, int?, String)>[
          ([0x41, 0x1f600, 0xdfff], 0, null, 'A\u{1F600}\uDFFF'),
          ([0x41, 0x1f600, 0xdfff], 1, 2, '\u{1F600}'),
          ([0x41], 3, 99, ''),
          ([-1, 0x41], 1, null, 'A'),
        ]) {
      expect(runner.run(function, [codes, start, end]), expected);
    }
    expect(() => runner.run(function, [<int>[], -1, null]), throwsRangeError);
    expect(() => runner.run(function, [<int>[], 2, 1]), throwsRangeError);
    expect(
      () => runner.run(function, [
        [0x110000],
        0,
        null,
      ]),
      throwsArgumentError,
    );
  });

  test(
    'inline scalar access retains the managed base and validates operands',
    () {
      final block = Block([.string, .integer]);
      final [object, offset] = block.parameters;
      final load = LoadObjectData(object, offset, .new(Uint16));
      final store = StoreObjectData(
        object,
        offset,
        .new(Uint16),
        const Constant.integer(65),
      );
      expect(load.inputs, [object, offset]);
      expect(load.type, ValueType.integer);
      expect(store.inputs, [object, offset, const Constant.integer(65)]);
      expect(store.effects, {Effect.writesStorage});
      for (final invalid in [
        const Constant.nullValue(),
        const Constant.integer(0),
        const Constant.floating(0),
      ]) {
        expect(
          () => LoadObjectData(invalid, offset, .new(Uint16)),
          throwsArgumentError,
        );
      }
      expect(
        () => StoreObjectData(object, offset, .new(Uint16), object),
        throwsArgumentError,
      );
      expect(
        () => LoadObjectData(object, object, .new(Uint16)),
        throwsArgumentError,
      );
      final create = StringFromCharCode(offset);
      expect(create.effects, {Effect.allocates, Effect.mayThrow});
      expect(() => StringFromCharCode(object), throwsArgumentError);
      final codes = SequenceConstant(CoreTypes.listOf(.integer), [
        const Constant.integer(65),
      ]);
      final createMany = StringFromCharCodes(codes);
      expect(createMany.inputs, [
        codes,
        const Constant.integer(0),
        const Constant.nullValue(),
      ]);
      expect(
        createMany.effects,
        containsAll([Effect.callsUserCode, Effect.allocates, Effect.mayThrow]),
      );
      expect(() => StringFromCharCodes(object), throwsArgumentError);
      expect(() => StringFromCharCodes(codes, object), throwsArgumentError);
      expect(
        () => StringFromCharCodes(codes, offset, object),
        throwsArgumentError,
      );
    },
  );
  test('string access validates operands and preserves effects', () {
    const text = Constant.string('');
    final length = StringLength(text);
    final unit = StringCodeUnitAt(text, const Constant.integer(0));
    expect(length.type, ValueType.integer);
    expect(length.effects, {Effect.readsStorage});
    expect(unit.type, ValueType.integer);
    expect(unit.effects, {Effect.readsStorage, Effect.mayThrow});
    expect(() => StringLength(const Constant.nullValue()), throwsArgumentError);
    expect(
      () => StringCodeUnitAt(text, const Constant.floating(0)),
      throwsArgumentError,
    );
  });

  test(
    'code-unit access preserves UTF-16 units and rejects invalid indices',
    () {
      final target = FunctionTarget(
        Uri.parse('memory:strings'),
        'read',
        .integer,
        [.string, .integer],
      );
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            StringCodeUnitAt(entry.parameters[0], entry.parameters[1]),
          ),
        ),
      );
      final function = IrFunction(target, [entry]);
      final runner = IrInterpreter(IrProgram([], [function]), {});
      const text = 'A\u0000\u{1F600}\uDFFF';
      const units = [0x41, 0, 0xd83d, 0xde00, 0xdfff];
      for (final (index, unit) in units.indexed) {
        expect(runner.run(function, [text, index]), unit);
      }
      for (final index in [-1, units.length]) {
        expect(() => runner.run(function, [text, index]), throwsRangeError);
      }
    },
  );
}
