import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _value = HirField('value', .integer);
final _integers = HirClass('Integer', null, [_value]);
final _number = HirField('number', .float);
final _floats = HirClass('Float', null, [_number]);
final _held = HirField('held', .reference);
final _holder = HirClass('Holder', null, [_held]);
final _get = HirSelector('get', const [], .integer);
final _isInteger = HirTypeTest('integer'), _isHolder = HirTypeTest('holder');

const _min = -0x8000000000000000, _max = 0x7fffffffffffffff;
const _values = [
  0, 1, -1, 2, 1000, -1000, //
  0x3fffffffffffffff, 0x4000000000000000, -0x4000000000000000,
  -0x4000000000000001, _max, _min,
];

HirFunction _getter(String name, HirValue Function(HirBlock, HirValue) build) {
  final block = HirBlock([.reference]);
  block.end(HirReturn(build(block, block.parameters.single)));
  return HirFunction(name, const [.reference], .integer)..define([block]);
}

/// A program that exits with the number of the first check that fails, or 0.
HirModule _checking(
  List<HirValue> Function(HirBlock block) checks, {
  bool hasIntegers = true,
}) {
  var block = HirBlock();
  final blocks = [block];
  for (final (i, check) in checks(block).indexed) {
    final next = HirBlock(), failed = HirBlock();
    block.end(HirBranch(check, HirEdge(next), HirEdge(failed)));
    failed.end(HirExit(failed.add(HirConst(i + 1))));
    blocks.addAll([failed, next]);
    block = next;
  }
  block.end(HirReturn());
  final main = HirFunction('main', const [])..define(blocks);
  final ofInteger = _getter('integer', (b, o) => b.add(HirUnbox(_value, o)));
  final ofHolder = _getter('holder', (b, _) => b.add(HirConst(77)));
  return HirModule(
    main,
    [main, ofInteger, ofHolder],
    classes: [_holder, _floats, _integers],
    dispatch: {
      _get: {_integers: ofInteger, _holder: ofHolder},
    },
    tests: {
      _isInteger: {_integers},
      _isHolder: {_holder},
    },
    integers: hasIntegers ? _integers : null,
  );
}

void _agrees(String name, List<HirValue> Function(HirBlock block) checks) =>
    test(name, () async {
      for (final hasIntegers in [true, false]) {
        final module = _checking(checks, hasIntegers: hasIntegers);
        expect(HirInterpreter(module).run(), isNull);
        expect(LoweredRun(module).code, isNull);
      }
    });

void main() {
  HirValue equal(HirBlock block, HirValue a, Object b) =>
      block.add(HirCompare(.equal, a, block.add(HirConst(b))));

  _agrees('integers are in boxes and come out', (block) {
    return [
      for (final value in _values)
        () {
          final box = block.add(HirBox(_integers, block.add(HirConst(value))));
          return equal(block, block.add(HirUnbox(_value, box)), value);
        }(),
    ];
  });

  _agrees('doubles are in boxes and come out', (block) {
    return [
      for (final value in [0.5, -1e300, 4.0])
        () {
          final box = block.add(HirBox(_floats, block.add(HirConst(value))));
          return equal(block, block.add(HirUnbox(_number, box)), value);
        }(),
    ];
  });

  _agrees('boxes have their class', (block) {
    return [
      for (final value in _values) ...[
        for (final (test, expected) in [(_isInteger, true), (_isHolder, false)])
          () {
            final box = block.add(
              HirBox(_integers, block.add(HirConst(value))),
            );
            final found = block.add(HirIsInstance(test, box));
            return equal(block, found, expected);
          }(),
        () {
          final box = block.add(HirBox(_integers, block.add(HirConst(value))));
          return equal(block, block.add(HirVirtualCall(_get, box, [])), value);
        }(),
        () {
          final box = block.add(HirBox(_integers, block.add(HirConst(value))));
          final number = block.add(HirMachine(.classNumber, [box]));
          return equal(block, number, 2);
        }(),
      ],
    ];
  });

  _agrees('refined boxes are the same boxes', (block) {
    return [
      for (final value in _values)
        () {
          final box = block.add(HirBox(_integers, block.add(HirConst(value))));
          final refined = block.add(HirRefine(box, {_integers}));
          return equal(block, block.add(HirUnbox(_value, refined)), value);
        }(),
    ];
  });

  _agrees('fields hold boxes and objects', (block) {
    final holder = block.add(HirNew(_holder));
    return [
      for (final value in _values)
        () {
          final box = block.add(HirBox(_integers, block.add(HirConst(value))));
          block.add(HirStore(_held, holder, box));
          final held = block.add(HirLoad(_held, holder));
          return equal(block, block.add(HirUnbox(_value, held)), value);
        }(),
      () {
        block.add(HirStore(_held, holder, holder));
        final held = block.add(HirLoad(_held, holder));
        return equal(block, block.add(HirVirtualCall(_get, held, [])), 77);
      }(),
    ];
  });

  _agrees('constants are boxes', (block) {
    return [
      for (final value in _values) ...[
        () {
          final box = block.add(
            HirStatic(HirConstObject(_integers, {_value: value})),
          );
          return equal(block, block.add(HirUnbox(_value, box)), value);
        }(),
        () {
          final box = HirConstObject(_integers, {_value: value});
          final holder = HirConstObject(_holder, {_held: box});
          final held = block.add(HirLoad(_held, block.add(HirStatic(holder))));
          return equal(block, block.add(HirVirtualCall(_get, held, [])), value);
        }(),
      ],
    ];
  });
}
