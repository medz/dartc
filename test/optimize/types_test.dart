import 'package:dartc/hir.dart';
import 'package:dartc/optimize.dart';
import 'package:test/test.dart';

final _value = HirField('value', .integer);
final _integers = HirClass('Integer', null, [_value]);
final _a = HirClass('A', null, const []);
final _kind = HirField('kind', .integer);
final _types = HirClass('Type', null, [_kind]);
final _isInteger = HirTypeTest('integer');
final _integerType = HirConstObject(_types, {_kind: 1});
final _otherType = HirConstObject(_types, {_kind: 2});

/// What stands for the runtime: it ends the program with 9, so that the
/// program tells whether it was asked.
final HirFunction _isInstance = () {
  final block = HirBlock([.reference, .reference]);
  block.end(HirExit(block.add(HirConst(9))));
  return HirFunction('isInstance', const [.reference, .reference], .boolean)
    ..define([block]);
}();

/// Gives its argument; it is not small, so that it is not inlined.
final HirFunction _opaque = () {
  final block = HirBlock([.reference]);
  for (var i = 0; i < 20; i++) {
    block.add(HirMachine(.steadyTime, const []));
  }
  block.end(HirReturn(block.parameters.single));
  return HirFunction('opaque', const [.reference], .reference)..define([block]);
}();

/// A program that exits with 1 if `isInstance` of what [object] gives and
/// [type] is true, and with 0 if not.
HirModule _testing(
  HirValue Function(HirBlock block) object, [
  HirConstObject? type,
]) {
  final entry = HirBlock(), yes = HirBlock(), no = HirBlock();
  final value = object(entry);
  final given = entry.add(HirStatic(type ?? _integerType));
  final isOf = entry.add(HirCall(_isInstance, [value, given]));
  entry.end(HirBranch(isOf, HirEdge(yes), HirEdge(no)));
  yes.end(HirExit(yes.add(HirConst(1))));
  no.end(HirExit(no.add(HirConst(0))));
  final main = HirFunction('main', const [])..define([entry, yes, no]);
  return HirModule(
    main,
    [main, _isInstance, _opaque],
    classes: [_integers, _a, _types],
    tests: {
      _isInteger: {_integers},
    },
    integers: _integers,
    isInstance: _isInstance,
    sealedTypes: {_integerType: _isInteger},
  );
}

HirValue _integer(HirBlock block) =>
    block.add(HirBox(_integers, block.add(HirConst(5))));

/// What an object of unknown class gives, unboxed and boxed again.
HirValue _reboxed(HirBlock block) {
  final given = block.add(HirCall(_opaque, [_integer(block)]));
  final number = block.add(HirUnbox(_value, given));
  return block.add(HirBox(_integers, number));
}

/// What [module] exits with after it is optimized with [enabled]: 9 if it
/// asks the runtime.
int? _run(
  HirModule module, {
  Set<Optimization> enabled = const {...Optimization.values},
}) {
  final result = optimizeProgram(module, enabled: enabled);
  verifyHir(result);
  return HirInterpreter(result).run();
}

final _withoutDeciding = {...Optimization.values}
  ..remove(Optimization.decideTypes);

void main() {
  test('tests of sealed types are answered by known classes', () {
    expect(_run(_testing(_integer)), 1);
    expect(_run(_testing((block) => block.add(HirNew(_a)))), 0);
  });

  test('and are kept without the optimization', () {
    expect(_run(_testing(_integer), enabled: _withoutDeciding), 9);
  });

  test('but not where the class is not known or the type is not sealed', () {
    final unknown = _testing(
      (block) => block.add(HirCall(_opaque, [_integer(block)])),
    );
    expect(_run(unknown), 9);
    expect(_run(_testing(_integer, _otherType)), 9);
  });

  test('what a box tells stays known when it is made anew', () {
    final first = optimizeProgram(
      _testing(_reboxed),
      enabled: _withoutDeciding,
    );
    expect(printHir(first), contains('as Integer'));
    expect(HirInterpreter(first).run(), 9);
    expect(_run(first), 1);
  });
}
