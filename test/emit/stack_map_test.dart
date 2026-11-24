import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/src/emit/allocate.dart';
import 'package:dartc/src/emit/arm64/registers.dart';
import 'package:dartc/src/emit/selection.dart';
import 'package:dartc/src/emit/stack_maps.dart';
import 'package:dartc/src/emit/support.dart';
import 'package:test/test.dart';

import '../lir/support.dart';
import 'random_lir.dart';
import 'support.dart';

final _pair = LirSignature([.ref, .ref], .ref);

/// A module whose function `f` is built by [build]; `g` takes and gives
/// references.
LirModule _module(
  List<LirType> parameters,
  LirValue? Function(LirBlock block, List<LirParameter> p) build,
) => LirModule(
  functions: [
    function('f', parameters, .ref, build),
    function('g', [.ref, .ref], .ref, (_, p) => p[1]),
  ],
);

Set<LirValue> _liveAfter(LirFunction function, LirCall call) =>
    livenessOf(function).liveAfter(call);

void main() {
  test('exactly the values used after a call are alive across it', () {
    late LirCall first, second;
    late List<LirParameter> p;
    final made = function('f', [.ref, .ref, .i64], .ref, (block, parameters) {
      p = parameters;
      first = block.add(Call('g', _pair, [p[0], p[1]]));
      second = block.add(Call('g', _pair, [first, p[1]]));
      block.add(Store(.i64, second, p[2]));
      return p[0];
    });
    expect(_liveAfter(made, first), {p[0], p[1], p[2]});
    expect(_liveAfter(made, second), {p[0], p[2]});
  });

  test('a value of one branch is not alive in the other', () {
    final entry = LirBlock([.i64, .ref]);
    final left = LirBlock(), right = LirBlock(), more = LirBlock();
    final [condition, object] = entry.parameters;
    entry.end(Branch(condition, LirEdge(left), LirEdge(right)));
    final made = left.add(Call('g', _pair, [object, object]));
    left.end(Jump(LirEdge(more)));
    final other = right.add(Call('g', _pair, [object, object]));
    right.end(Return(other));
    final last = more.add(Call('g', _pair, [made, made]));
    more.end(Return(more.add(Call('g', _pair, [made, last]))));
    final function = LirFunction('f', LirSignature([.i64, .ref], .ref), [
      entry,
      left,
      right,
      more,
    ]);
    expect(_liveAfter(function, other), isEmpty);
    expect(_liveAfter(function, made), isEmpty);
    expect(_liveAfter(function, last), {made});
  });

  test('a loop keeps what its next round needs', () {
    final entry = LirBlock([.ref, .i64]), loop = LirBlock([.i64]);
    final exit = LirBlock();
    final [object, count] = entry.parameters;
    entry.end(Jump(LirEdge(loop, [count])));
    final call = loop.add(Call('g', _pair, [object, object]));
    final rest = loop.add(
      IntBinary(.sub, loop.parameters[0], loop.add(ConstInt(1))),
    );
    loop.end(Branch(rest, LirEdge(loop, [rest]), LirEdge(exit)));
    exit.end(Return(call));
    final function = LirFunction('f', LirSignature([.ref, .i64], .ref), [
      entry,
      loop,
      exit,
    ]);
    expect(_liveAfter(function, call), {object, loop.parameters[0]});
  });

  test('references alive across calls are on the stack', () {
    var found = 0;
    for (var seed = 0; seed < 60; seed++) {
      for (final made in RandomLir(seed).functions()) {
        final liveness = livenessOf(made);
        final allocation = Allocation(liveness, arm64Registers.values);
        for (final block in made.blocks) {
          for (final call in callsOf(block)) {
            for (final value in liveness.liveAfter(call)) {
              expect(liveness.intervals[value]!.crossesCall, isTrue);
              if (value.type != .ref) continue;
              found++;
              final home = allocation.homes[value];
              expect(home ?? allocation.locations[value], isA<OnStack>());
            }
          }
        }
      }
    }
    expect(found, greaterThan(100));
  });

  test('what a handler needs is on the stack', () {
    var found = 0;
    for (var seed = 0; seed < 60; seed++) {
      for (final made in RandomLir(seed).functions()) {
        final allocation = Allocation(livenessOf(made), arm64Registers.values);
        for (final block in made.blocks) {
          if (block.terminator case Invoke(:final onThrow)) {
            for (final value in onThrow.arguments) {
              if (Selection.constantOf(value) != null) continue;
              found++;
              expect(allocation.locations[value], isA<OnStack>());
            }
          }
        }
      }
    }
    expect(found, greaterThan(50));
  });

  test('throw targets are encoded for the runtime', () {
    final bytes = encodeThrowTargets(const [
      ThrowTarget(100, 200),
      ThrowTarget(104, 60),
    ]);
    expect(bytes.buffer.asInt32List(), [2, 100, 200, 104, 60]);
  });

  test('targets follow the calls that return to them', () {
    final entry = LirBlock([.i64]), normal = LirBlock([.ref]);
    final handler = LirBlock([.ref, .ref]);
    entry.end(
      Invoke(Alloc(entry.parameters[0]), LirEdge(normal), LirEdge(handler)),
    );
    normal.end(Return());
    handler.end(Return());
    final code = emitCode(
      LirModule(
        functions: [
          function(allocateSymbol, [.i64], .ref, (block, _) {
            return block.add(ConstNull());
          }),
          LirFunction('f', LirSignature([.i64]), [entry, normal, handler]),
        ],
      ),
    );
    final ThrowTarget(:returnOffset, :target) = code.throwTargets.single;
    expect(code.stackMaps.single.returnOffset, returnOffset);
    expect(target, greaterThan(returnOffset));
    expect(code.data, isEmpty);
  });

  test('each call lists the stack words of its live references', () {
    final module = _module([.ref, .ref, .i64], (block, p) {
      final first = block.add(Call('g', _pair, [p[0], p[1]]));
      final second = block.add(Call('g', _pair, [first, p[1]]));
      block.add(Store(.i64, second, p[2]));
      return p[0];
    });
    final maps = emitCode(module).stackMaps;
    expect(maps, hasLength(2));
    final [first, second] = maps;
    expect(first.returnOffset, lessThan(second.returnOffset));
    // Below the frame, in distinct words.
    for (final map in maps) {
      expect(
        map.offsets,
        everyElement(allOf(isNegative, (int o) => o % 8 == 0)),
      );
      expect(map.offsets.toSet(), hasLength(map.offsets.length));
    }
    expect(first.offsets, hasLength(2));
    expect(second.offsets, hasLength(1));
    expect(first.offsets, containsAll(second.offsets));
  });

  test('return addresses are those of the calls', () {
    final code = emitCode(
      _module([.ref], (block, p) {
        final address = block.add(SymbolAddress('g'));
        final first = block.add(Call('g', _pair, [p[0], p[0]]));
        return block.add(CallIndirect(address, _pair, [first, p[0]]));
      }),
    );
    final words = ByteData.sublistView(code.text);
    final found = [
      for (final map in code.stackMaps)
        words.getUint32(map.returnOffset - 4, .little),
    ];
    expect(found, [0x94000000, 0xd63f0100]);
  });

  test('allocation is a call too', () {
    final module = LirModule(
      functions: [
        function('f', [.ref], .ref, (block, p) {
          block.add(Alloc(block.add(ConstInt(16))));
          return p[0];
        }),
        function('.allocate', [.i64], .ref, (block, _) {
          return block.add(ConstNull());
        }),
      ],
    );
    expect(emitCode(module).stackMaps.single.offsets, hasLength(1));
  });

  test('allocation needs its function', () {
    final module = _module([], (block, _) {
      return block.add(Alloc(block.add(ConstInt(16))));
    });
    expect(
      () => emitCode(module),
      throwsA(
        isA<EmitUnsupported>().having(
          (e) => '$e',
          'text',
          contains('.allocate'),
        ),
      ),
    );
  });

  test('the encoded table can be searched', () {
    final maps = [
      StackMap(8, []),
      StackMap(24, [-16, -40]),
      StackMap(100, []),
      StackMap(104, [-16, -40]),
    ];
    final data = ByteData.sublistView(encodeStackMaps(maps));
    expect(data.getUint32(0, .little), 4);
    for (final (i, map) in maps.indexed) {
      expect(data.getUint32(4 + i * 8, .little), map.returnOffset);
      final record = data.getUint32(8 + i * 8, .little);
      expect(data.getUint32(record, .little), map.offsets.length);
      expect([
        for (var j = 0; j < map.offsets.length; j++)
          data.getInt32(record + 4 + j * 4, .little),
      ], map.offsets);
    }
    // Equal records are stored once.
    expect(data.lengthInBytes, 4 + 4 * 8 + 4 + 12);
    expect(encodeStackMaps([]), [0, 0, 0, 0]);
  });

  test('the runtime can find both tables', () {
    final code = emitCode(
      LirModule(
        functions: [
          function('f', [], null, (block, _) {
            block
              ..add(SymbolAddress(stackMapSymbol))
              ..add(SymbolAddress(textSymbol));
            return null;
          }),
        ],
      ),
    );
    expect(code.functions[textSymbol], 0);
    expect(code.data[stackMapSymbol], encodeStackMaps(code.stackMaps));
    // Programs without a collector do not carry them.
    expect(emitCode(_module([.ref], (_, p) => p[0])).data, isEmpty);
  });
}
