import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _n = HirField('n', .integer);
final _a = HirClass('A', null, [_n]), _b = HirClass('B', _a, []);
final _isB = HirTypeTest('B');

/// Throws a new A or B holding its first argument, unless that is 0.
final HirFunction _raise = () {
  final entry = HirBlock([.integer, .boolean]);
  final bad = HirBlock(), fine = HirBlock();
  final [n, isB] = entry.parameters;
  final zero = entry.add(HirConst(0));
  final ends = entry.add(HirCompare(.equal, n, zero));
  entry.end(HirBranch(ends, HirEdge(fine), HirEdge(bad)));
  fine.end(HirReturn(fine.add(HirConst(5))));
  final a = HirBlock(), b = HirBlock(), thrower = HirBlock([.reference]);
  bad.end(HirBranch(isB, HirEdge(b), HirEdge(a)));
  a.end(HirJump(HirEdge(thrower, [a.add(HirNew(_a))])));
  b.end(HirJump(HirEdge(thrower, [b.add(HirNew(_b))])));
  final object = thrower.parameters.single;
  thrower
    ..add(HirStore(_n, object, n))
    ..end(HirThrow(object, thrower.add(HirNew(_a))));
  return HirFunction('raise', [.integer, .boolean], .integer)
    ..define([entry, fine, bad, a, b, thrower]);
}();

HirModule _module(
  HirFunction main,
  List<HirFunction> others, {
  HirFunction? stackOverflow,
  HirFunction? uncaught,
  HirFunction? raise,
  HirFunction? outOfMemory,
  List<HirClass>? classes,
  Map<HirTypeTest, Set<HirClass>>? tests,
}) => HirModule(
  main,
  [main, ...others, ?stackOverflow, ?uncaught, ?raise, ?outOfMemory],
  classes: classes ?? [_a, _b],
  tests:
      tests ??
      {
        _isB: {_b},
      },
  stackOverflow: stackOverflow,
  uncaught: uncaught,
  raise: raise,
  outOfMemory: outOfMemory,
);

/// Exits with what a call of `raise` gives, or with 100 and more if it throws.
HirModule _catching(int n, {required bool isB}) {
  final entry = HirBlock(), normal = HirBlock([.integer, .integer]);
  final handler = HirBlock([.reference, .reference, .integer]);
  final seven = entry.add(HirConst(7)), hundred = entry.add(HirConst(100));
  final call = HirCall(_raise, [
    entry.add(HirConst(n)),
    entry.add(HirConst(isB)),
  ]);
  entry.end(
    HirInvoke(call, HirEdge(normal, [seven]), HirEdge(handler, [hundred])),
  );
  normal.end(
    HirExit(
      normal.add(
        HirIntBinary(.add, normal.parameters[0], normal.parameters[1]),
      ),
    ),
  );
  final [exception, _, base] = handler.parameters;
  final found = handler.add(HirLoad(_n, exception));
  final sum = handler.add(HirIntBinary(.add, base, found));
  final yes = HirBlock(), no = HirBlock();
  handler.end(
    HirBranch(
      handler.add(HirIsInstance(_isB, exception)),
      HirEdge(yes),
      HirEdge(no),
    ),
  );
  no.end(HirExit(sum));
  yes.end(HirExit(yes.add(HirIntBinary(.add, sum, yes.add(HirConst(50))))));
  final main = HirFunction('main', const [])
    ..define([entry, normal, handler, yes, no]);
  return _module(main, [_raise]);
}

HirFunction _ending(
  String name,
  List<HirType> parameters,
  HirTerminator Function(HirBlock block) build,
) {
  final block = HirBlock(parameters);
  block.end(build(block));
  return HirFunction(name, parameters)..define([block]);
}

void main() {
  group('interpreter', () {
    test('an invocation continues on one of its edges', () {
      expect(HirInterpreter(_catching(0, isB: true)).run(), 12);
      expect(HirInterpreter(_catching(3, isB: false)).run(), 103);
      expect(HirInterpreter(_catching(3, isB: true)).run(), 153);
    });

    test('a program ends with what nothing catches', () {
      final main = _ending('main', [], (block) {
        block.add(
          HirCall(_raise, [block.add(HirConst(3)), block.add(HirConst(false))]),
        );
        return HirReturn();
      });
      final uncaught = _ending('uncaught', [.reference, .reference], (block) {
        writeText(block, 1, 'out\n');
        writeText(block, 2, 'a ');
        writeText(block, 2, 'b\n');
        return HirReturn();
      });
      final run = HirInterpreter(_module(main, [_raise], uncaught: uncaught));
      expect(run.run(), 255);
      expect(run.errors, 'a b\n');
      expect(run.output, 'out\n');
      final plain = HirInterpreter(_module(main, [_raise]));
      expect(plain.run, throwsStateError);
    });

    test('deep calls overflow the stack', () {
      HirModule recursing(int depth, {required bool checksStack}) {
        final entry = HirBlock([.integer]);
        final more = HirBlock(), done = HirBlock();
        final f = HirFunction('f', [.integer], null, checksStack);
        final n = entry.parameters.single;
        final ends = entry.add(HirCompare(.equal, n, entry.add(HirConst(0))));
        entry.end(HirBranch(ends, HirEdge(done), HirEdge(more)));
        final one = more.add(HirConst(1));
        final rest = more.add(HirIntBinary(.subtract, n, one));
        more
          ..add(HirCall(f, [rest]))
          ..end(HirReturn());
        done.end(HirReturn());
        f.define([entry, more, done]);
        final start = HirBlock(), normal = HirBlock();
        final handler = HirBlock([.reference, .reference]);
        start.end(
          HirInvoke(
            HirCall(f, [start.add(HirConst(depth))]),
            HirEdge(normal),
            HirEdge(handler),
          ),
        );
        normal.end(HirExit(normal.add(HirConst(1))));
        handler.end(HirExit(handler.add(HirConst(2))));
        final overflow = _ending('overflow', [], (block) {
          final object = block.add(HirNew(_a));
          return HirThrow(object, object);
        });
        final main = HirFunction('main', const [])
          ..define([start, normal, handler]);
        return _module(main, [f], stackOverflow: overflow);
      }

      int? run(int depth, {bool checksStack = true}) => HirInterpreter(
        recursing(depth, checksStack: checksStack),
        maxDepth: 100,
      ).run();
      expect(run(90), 1);
      expect(run(110), 2);
      expect(run(110, checksStack: false), 1);
    });

    test('doubles become ints, up to the largest', () {
      for (final value in doubles.where((value) => value.isFinite)) {
        final module = body((block) {
          final whole = block.add(
            HirUnary(.floatToInt, block.add(HirConst(value))),
          );
          return HirExit(whole);
        });
        expect(HirInterpreter(module).run(), value.toInt());
      }
      final module = body((block) {
        block.add(HirUnary(.floatToInt, block.add(HirConst(double.nan))));
        return HirReturn();
      });
      expect(HirInterpreter(module).run, throwsStateError);
    });

    test('division and shifts must be possible', () {
      for (final operator in HirIntOperator.values) {
        if (!operator.isDivision && !operator.isShift) continue;
        final module = body((block) {
          final one = block.add(HirConst(1));
          final wrong = block.add(HirConst(operator.isDivision ? 0 : -1));
          block.add(HirIntBinary(operator, one, wrong));
          return HirReturn();
        });
        expect(HirInterpreter(module).run, throwsStateError);
      }
    });

    test('only objects have a class', () {
      final main = _ending('main', [], (block) {
        block.add(HirIsInstance(_isB, block.add(HirNull())));
        return HirReturn();
      });
      expect(HirInterpreter(_module(main, [])).run, throwsStateError);
    });

    test('errors of the machine are collected', () {
      final module = body((block) {
        writeText(block, 2, 'hé');
        writeText(block, 2, 'i');
        return HirReturn();
      });
      final run = HirInterpreter(module)..run();
      expect(run.errors, 'héi');
    });
  });

  test('prints', () {
    final text = printHir(_catching(3, isB: true));
    expect(text, contains('test B: B\n'));
    expect(text, contains('  invoke raise(v2, v3), b1(v0), throw b2(v1)\n'));
    expect(text, contains(' is B\n'));
    expect(RegExp(r'  throw v\d+, v\d+\n').hasMatch(text), isTrue);
    final errors = body((block) {
      final half = block.add(HirConst(0.5));
      block.add(HirUnary(.floatToInt, half));
      return HirReturn();
    });
    expect(printHir(errors), contains('v1 = int v0'));
  });

  group('rejects', () {
    void rejects(String message, HirModule Function() build) =>
        test(message, () {
          expect(
            () => verifyHir(build()),
            throwsA(
              isA<HirError>().having(
                (e) => e.message,
                'message',
                contains(message),
              ),
            ),
          );
        });

    HirModule ending(
      HirTerminator Function(HirBlock block) build, [
      List<HirBlock> more = const [],
    ]) {
      final block = HirBlock();
      block.end(build(block));
      final main = HirFunction('main', const [])..define([block, ...more]);
      return _module(main, [_raise]);
    }

    rejects('exception: expected reference', () {
      return ending((block) {
        return HirThrow(block.add(HirConst(1)), block.add(HirNull()));
      });
    });
    rejects('stack trace: expected reference', () {
      return ending((block) {
        return HirThrow(block.add(HirNull()), block.add(HirConst(1)));
      });
    });
    rejects('is B: expected reference', () {
      return ending((block) {
        block.add(HirIsInstance(_isB, block.add(HirConst(1))));
        return HirReturn();
      });
    });
    rejects('unlisted test C', () {
      return ending((block) {
        block.add(HirIsInstance(HirTypeTest('C'), block.add(HirNull())));
        return HirReturn();
      });
    });
    rejects('test B: unlisted class B', () {
      return _module(_ending('main', [], (_) => HirReturn()), [], classes: []);
    });

    HirModule invoking({
      List<HirType> normal = const [.integer],
      List<HirType> handler = const [.reference, .reference],
      int arguments = 2,
      HirInstruction? call,
    }) {
      final onReturn = HirBlock(normal)..end(HirReturn());
      final onThrow = HirBlock(handler)..end(HirReturn());
      return ending((block) {
        final values = [block.add(HirConst(1)), block.add(HirConst(true))];
        return HirInvoke(
          HirCall(_raise, values.take(arguments)),
          HirEdge(onReturn),
          HirEdge(onThrow),
        );
      }, [onReturn, onThrow]);
    }

    test('accepts a right invocation', () => verifyHir(invoking()));
    rejects('edge target does not accept the call outcome', () {
      return invoking(normal: []);
    });
    rejects('edge target does not accept the call outcome', () {
      return invoking(normal: [.float]);
    });
    rejects('edge target does not accept the call outcome', () {
      return invoking(handler: [.reference]);
    });
    rejects('edge arguments', () {
      return invoking(handler: [.reference, .reference, .integer]);
    });
    rejects('call to raise', () => invoking(arguments: 1));
    rejects('invoke shares one edge for both outcomes', () {
      final target = HirBlock([.reference, .reference])..end(HirReturn());
      final edge = HirEdge(target);
      return ending((block) {
        return HirInvoke(HirNew(_a), edge, edge);
      }, [target]);
    });
    rejects('a value is defined twice', () {
      final normal = HirBlock([.reference])..end(HirReturn());
      final handler = HirBlock([.reference, .reference])..end(HirReturn());
      return ending((block) {
        return HirInvoke(
          block.add(HirNew(_a)),
          HirEdge(normal),
          HirEdge(handler),
        );
      }, [normal, handler]);
    });
    rejects('use of an undefined value', () {
      final normal = HirBlock([.reference]);
      final handler = HirBlock([.reference, .reference])..end(HirReturn());
      final call = HirNew(_a);
      normal
        ..add(HirLoad(_n, call))
        ..end(HirReturn());
      return ending((block) {
        return HirInvoke(call, HirEdge(normal), HirEdge(handler));
      }, [normal, handler]);
    });

    final wrong = _ending('wrong', [.float], (_) => HirReturn());
    HirFunction main() => _ending('main', [], (_) => HirReturn());
    for (final (name, build) in <(String, HirModule Function(HirFunction f))>[
      ('stackOverflow', (f) => _module(main(), [], stackOverflow: f)),
      ('outOfMemory', (f) => _module(main(), [], outOfMemory: f)),
      ('uncaught', (f) => _module(main(), [], uncaught: f)),
      ('raise', (f) => _module(main(), [], raise: f)),
    ]) {
      rejects('$name has another signature', () => build(wrong));
    }
    rejects('raise is not listed', () {
      final start = main();
      return HirModule(start, [start], raise: _raise);
    });
  });
}
