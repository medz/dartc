import 'dart:math';
import 'dart:typed_data';

import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import '../hir/support.dart';
import 'support.dart';

final _head = HirField('head', .reference);
final _list = HirClass('List', null, [_head], .references);
final _bytes = HirClass('Bytes', null, [], .bytes);
final _plain = HirClass('Plain', null, []);

/// What lowered code exits with, given the value of [build].
int? _run(HirValue Function(HirBlock block) build) {
  final module = body((block) => HirExit(build(block)));
  return runLowered(
    HirModule(module.main, module.functions, classes: [_plain, _list, _bytes]),
  );
}

HirValue _number(HirBlock block, int value) => block.add(HirConst(value));

void main() {
  test('arrays have a length, a field and elements', () {
    expect(
      _run((block) {
        final array = block.add(HirNewArray(_list, _number(block, 3)));
        final inner = block.add(HirNewArray(_bytes, _number(block, 40)));
        final two = _number(block, 2);
        block
          ..add(HirStoreElement(.reference, array, two, inner))
          ..add(HirStore(_head, array, array));
        final again = block.add(HirLoad(_head, array));
        final found = block.add(HirLoadElement(.reference, again, two));
        final own = block.add(HirLength(again));
        return block.add(HirIntBinary(.add, own, block.add(HirLength(found))));
      }),
      43,
    );
  });

  for (final (element, given, read) in [
    (HirElement.int8, 200, -56),
    (HirElement.uint8, 456, 200),
    (HirElement.int16, 0xffff, -1),
    (HirElement.uint16, -1, 0xffff),
    (HirElement.int32, 0xffffffff, -1),
    (HirElement.uint32, -1, 0xffffffff),
    (HirElement.int64, -5, -5),
  ]) {
    test('numbers are held as ${element.name}', () {
      expect(
        _run((block) {
          final array = block.add(HirNewArray(_bytes, _number(block, 16)));
          final at = _number(block, 3);
          block.add(HirStoreElement(element, array, at, _number(block, given)));
          return block.add(HirLoadElement(element, array, at));
        }),
        read,
      );
    });
  }

  for (final (element, bits) in [
    (HirElement.float64, 0x3fb999999999999a),
    (HirElement.float32, 0x3fb99999a0000000),
  ]) {
    test('numbers are held as ${element.name}', () {
      expect(
        _run((block) {
          final array = block.add(HirNewArray(_bytes, _number(block, 16)));
          final at = _number(block, 4);
          final value = block.add(HirConst(0.1));
          block.add(HirStoreElement(element, array, at, value));
          final found = block.add(HirLoadElement(element, array, at));
          return block.add(HirUnary(.floatBits, found));
        }),
        bits,
      );
    });
  }

  test('constant arrays hold their elements', () {
    final inner = HirConstObject(_bytes, const {}, [1, 2, 250]);
    final outer = HirConstObject(_list, {_head: inner}, [null, inner]);
    expect(
      _run((block) {
        final array = block.add(HirStatic(outer));
        final found = block.add(
          HirLoadElement(.reference, array, _number(block, 1)),
        );
        final head = block.add(HirLoad(_head, array));
        final last = block.add(
          HirLoadElement(.uint8, found, _number(block, 2)),
        );
        return block.add(HirIntBinary(.add, last, block.add(HirLength(head))));
      }),
      253,
    );
  });

  test('classes have numbers', () {
    expect(_run((block) => block.add(HirClassNumber(_bytes))), 2);
    expect(
      _run((block) {
        return block.add(HirClassNumber(HirClass('None', null, [])));
      }),
      -1,
    );
    expect(
      _run((block) {
        final array = block.add(HirNewArray(_list, _number(block, 1)));
        return block.add(HirMachine(.classNumber, [array]));
      }),
      1,
    );
  });

  test('doubles have bits and roots', () {
    expect(
      _run((block) {
        final nine = block.add(
          HirUnary(.bitsFloat, _number(block, 0x4022000000000000)),
        );
        final root = block.add(HirUnary(.squareRoot, nine));
        return block.add(HirUnary(.floatBits, root));
      }),
      0x4008000000000000,
    );
  });

  test('the system has functions of doubles', () {
    for (final (op, inputs, result) in [
      (HirMachineOp.sine, [1.0], sin(1.0)),
      (HirMachineOp.cosine, [1.0], cos(1.0)),
      (HirMachineOp.tangent, [1.0], tan(1.0)),
      (HirMachineOp.arcSine, [0.5], asin(0.5)),
      (HirMachineOp.arcCosine, [0.5], acos(0.5)),
      (HirMachineOp.arcTangent, [0.5], atan(0.5)),
      (HirMachineOp.exponential, [1.5], exp(1.5)),
      (HirMachineOp.logarithm, [1.5], log(1.5)),
      (HirMachineOp.arcTangent2, [1.0, 2.0], atan2(1.0, 2.0)),
      (HirMachineOp.power, [2.5, 3.5], pow(2.5, 3.5)),
    ]) {
      final bits = ByteData(8)..setFloat64(0, result.toDouble());
      expect(
        _run((block) {
          final found = block.add(
            HirMachine(op, [
              for (final input in inputs) block.add(HirConst(input)),
            ]),
          );
          return block.add(HirUnary(.floatBits, found));
        }),
        bits.getInt64(0),
        reason: op.name,
      );
    }
  });

  test('the system has times, zones and random bits', () {
    for (final op in [HirMachineOp.realTime, HirMachineOp.steadyTime]) {
      expect(_run((block) => block.add(HirMachine(op, const []))), isPositive);
    }
    expect(
      _run((block) => block.add(HirMachine(.randomBits, const []))),
      inInclusiveRange(0, 0xffffffff),
    );
    expect(
      _run((block) {
        final at = block.add(HirMachine(.outputBuffer, const []));
        block
          ..add(HirMachine(.store64, [at, _number(block, 1000000)]))
          ..add(HirMachine(.localTime, [at]));
        final zone = block.add(HirIntBinary(.add, at, _number(block, 48)));
        return block.add(HirMachine(.load64, [zone]));
      }),
      DateTime.fromMillisecondsSinceEpoch(1000000000).timeZoneOffset.inSeconds,
    );
  });

  test('an array can be created where throws are caught', () {
    final made = HirBlock([.reference]),
        failed = HirBlock([.reference, .reference]);
    made.end(HirExit(made.add(HirLength(made.parameters.single))));
    failed.end(HirExit(failed.add(HirConst(-1))));
    final entry = HirBlock();
    final length = entry.add(HirConst(9));
    entry.end(
      HirInvoke(HirNewArray(_bytes, length), HirEdge(made), HirEdge(failed)),
    );
    final main = HirFunction('main', const [])..define([entry, made, failed]);
    final raise = HirFunction('raise', [.reference, .reference])
      ..define([
        HirBlock([.reference, .reference])..end(HirUnreachable()),
      ]);
    expect(
      runLowered(
        HirModule(main, [main, raise], classes: [_bytes], raise: raise),
      ),
      9,
    );
  });
}
