import 'dart:math';

import 'package:dartc/hir.dart';
import 'package:test/test.dart';

final _value = HirField('value', .integer);
final _box = HirClass('Box', null, [_value]);
final _state = HirField('state', .integer);
final _frame = HirField('frame', .reference);
final _isDone = HirField('is done', .boolean);
final _result = HirField('result', .integer);
final _object = HirClass('Object', null, [_state, _frame, _isDone, _result]);

HirValue _number(HirBlock block, int value) => block.add(HirConst(value));

HirValue _wrap(HirBlock block, HirValue number) {
  final box = block.add(HirNew(_box));
  block.add(HirStore(_value, box, number));
  return box;
}

/// Gives a box with the number after the one that it is given, or throws that
/// if it can be divided by 3.
HirFunction _step() {
  final entry = HirBlock([.reference]);
  final given = entry.parameters.single;
  final number = entry.add(HirLoad(_value, given));
  final rest = entry.add(HirIntBinary(.modulo, number, _number(entry, 3)));
  final bad = HirBlock(), good = HirBlock();
  entry.end(
    HirBranch(
      entry.add(HirCompare(.equal, rest, _number(entry, 0))),
      HirEdge(bad),
      HirEdge(good),
    ),
  );
  bad.end(HirThrow(given, given));
  final next = good.add(HirIntBinary(.add, number, _number(good, 1)));
  good.end(HirReturn(_wrap(good, next)));
  return HirFunction('step', const [.reference], .reference)
    ..define([entry, bad, good]);
}

/// A random body, which calls [step] and works with a few numbers.
HirBlock _body(Random random, HirFunction step) {
  final entry = HirBlock(const [
    .reference,
    .reference,
    .reference,
    .reference,
  ]);
  var block = entry;
  var numbers = [for (var i = 1; i < 5; i++) _number(block, i)];
  HirValue any() => numbers[random.nextInt(numbers.length)];
  HirBlock join() => HirBlock([for (final _ in numbers) .integer]);
  void enter(HirBlock next) {
    block = next;
    numbers = [...next.parameters.skip(next.parameters.length - 4)];
  }

  void call() {
    final argument = _wrap(block, any());
    final at = random.nextInt(4);
    if (random.nextBool()) {
      final result = block.add(HirCall(step, [argument]));
      numbers[at] = block.add(HirLoad(_value, result));
      return;
    }
    final fine = HirBlock(const [
      .reference,
      .integer,
      .integer,
      .integer,
      .integer,
    ]);
    final thrown = HirBlock(const [
      .reference, .reference, .integer, .integer, .integer, .integer, //
    ]);
    block.end(
      HirInvoke(
        HirCall(step, [argument]),
        HirEdge(fine, numbers),
        HirEdge(thrown, numbers),
      ),
    );
    final after = join();
    for (final (next, add) in [(fine, 1), (thrown, 100)]) {
      enter(next);
      final number = block.add(HirLoad(_value, next.parameters.first));
      numbers[at] = block.add(HirIntBinary(.add, number, _number(block, add)));
      block.end(HirJump(HirEdge(after, numbers)));
    }
    enter(after);
  }

  void work(int depth) {
    for (var i = 1 + random.nextInt(3); i > 0; i--) {
      switch (random.nextInt(depth > 0 ? 6 : 3)) {
        case 0 || 1:
          call();
        case 2 || 3:
          final op = HirIntOperator.values[random.nextInt(3)];
          final result = block.add(HirIntBinary(op, any(), any()));
          final low = _number(block, 1023);
          numbers[random.nextInt(4)] = block.add(
            HirIntBinary(.and, result, low),
          );
        case 4:
          final left = HirBlock(), right = HirBlock(), after = join();
          final test = block.add(HirCompare(.less, any(), any()));
          block.end(HirBranch(test, HirEdge(left), HirEdge(right)));
          final before = numbers;
          for (final side in [left, right]) {
            block = side;
            numbers = [...before];
            work(depth - 1);
            block.end(HirJump(HirEdge(after, numbers)));
          }
          enter(after);
        default:
          final head = HirBlock(const [
            .integer,
            .integer,
            .integer,
            .integer,
            .integer,
          ]);
          block.end(HirJump(HirEdge(head, [_number(block, 3), ...numbers])));
          enter(head);
          final count = head.parameters.first;
          final body = HirBlock(), after = join();
          final test = block.add(
            HirCompare(.greater, count, _number(block, 0)),
          );
          block.end(HirBranch(test, HirEdge(body), HirEdge(after, numbers)));
          block = body;
          work(depth - 1);
          final less = block.add(
            HirIntBinary(.subtract, count, _number(block, 1)),
          );
          block.end(HirJump(HirEdge(head, [less, ...numbers])));
          enter(after);
      }
    }
  }

  work(3);
  var sum = numbers.first;
  for (final number in numbers.skip(1)) {
    final times = block.add(HirIntBinary(.multiply, sum, _number(block, 7)));
    sum = block.add(HirIntBinary(.add, times, number));
  }
  final self = entry.parameters.first;
  block
    ..add(HirStore(_result, self, sum))
    ..add(HirStore(_isDone, self, block.add(HirConst(true))))
    ..end(HirReturn(block.add(HirNull())));
  return entry;
}

const _signature = <HirType>[.reference, .reference, .reference, .reference];

/// Calls [body] until it is done, doing for it what [step] does.
int? _run(HirFunction body, HirFunction step, List<HirClass> classes) {
  final entry = HirBlock();
  final self = entry.add(HirNew(_object));
  entry
    ..add(HirStore(_state, self, _number(entry, 0)))
    ..add(HirStore(_isDone, self, entry.add(HirConst(false))));
  final none = entry.add(HirNull());
  final loop = HirBlock(const [.reference, .reference, .reference]);
  final thrown = HirBlock(const [.reference, .reference]);
  final left = HirBlock(const [.reference]);
  final done = HirBlock(), next = HirBlock();
  entry.end(HirJump(HirEdge(loop, [none, none, none])));
  loop.end(
    HirInvoke(
      HirCall(body, [self, ...loop.parameters]),
      HirEdge(left),
      HirEdge(thrown),
    ),
  );
  thrown.end(HirExit(_number(thrown, 99)));
  left.end(
    HirBranch(left.add(HirLoad(_isDone, self)), HirEdge(done), HirEdge(next)),
  );
  done.end(HirExit(done.add(HirLoad(_result, self))));
  final fine = HirBlock(const [.reference]);
  final failed = HirBlock(const [.reference, .reference]);
  next.end(
    HirInvoke(HirCall(step, left.parameters), HirEdge(fine), HirEdge(failed)),
  );
  fine.end(HirJump(HirEdge(loop, [fine.parameters.single, none, none])));
  failed.end(HirJump(HirEdge(loop, [none, ...failed.parameters])));
  final main = HirFunction('main', const [])
    ..define([entry, loop, left, next, fine, failed, done, thrown]);
  final module = HirModule(
    main,
    [main, body, step],
    classes: [_object, _box, ...classes],
  );
  verifyHir(module);
  return HirInterpreter(module).run();
}

List<HirBlock> _all(HirBlock entry) {
  final found = [entry];
  for (var i = 0; i < found.length; i++) {
    for (final edge in found[i].terminator!.edges) {
      if (!found.contains(edge.target)) found.add(edge.target);
    }
  }
  return found;
}

void main() {
  test('functions left in the middle do the same', () {
    final results = <int?>{};
    for (var seed = 0; seed < 300; seed++) {
      final step = _step();
      final whole = HirFunction('whole', _signature, .reference)
        ..define(_all(_body(Random(seed), step)));
      final expected = _run(whole, step, const []);
      final suspend = HirFunction('suspend', const [.reference], .reference);
      final (:blocks, :frame) = splitCoroutine(
        _body(Random(seed), suspend),
        HirCoroutine(suspend: suspend, state: _state, frame: _frame),
        'split',
      );
      final split = HirFunction('split', _signature, .reference)
        ..define(blocks);
      expect(_run(split, step, [?frame]), expected, reason: 'seed $seed');
      results.add(expected);
    }
    expect(results.length, greaterThan(50));
  });
}
