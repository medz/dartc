import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';
import 'package:test/test.dart';

import '../hir/support.dart';
import 'support.dart';

final _n = HirField('n', .integer);
final _a = HirClass('A', null, [_n]), _b = HirClass('B', _a, []);
final _c = HirClass('C', null, [_n]);
final _isA = HirTypeTest('A'), _isB = HirTypeTest('B');

HirFunction _function(
  String name,
  List<HirType> parameters,
  HirTerminator Function(HirBlock block) build, {
  HirType? result,
  bool checksStack = true,
}) {
  final block = HirBlock(parameters);
  block.end(build(block));
  return HirFunction(name, parameters, result, checksStack)..define([block]);
}

/// A program whose `main` calls [call] and exits with 1 if it throws, adding
/// what the exception's class is.
HirModule _module(
  HirCalling Function(HirBlock block) call,
  List<HirFunction> others, {
  HirFunction? stackOverflow,
  HirFunction? outOfMemory,
  HirFunction? allocate,
  HirFunction? raise,
  List<HirGlobal> globals = const [],
}) {
  final entry = HirBlock(), handler = HirBlock([.reference, .reference]);
  final made = call(entry);
  final normal = HirBlock([?made.type]);
  entry.end(HirInvoke(made, HirEdge(normal), HirEdge(handler)));
  normal.end(
    HirExit(
      made.type == .integer
          ? normal.parameters.single
          : normal.add(HirConst(0)),
    ),
  );
  final exits = <HirBlock>[];
  HirBlock exit(int code) {
    final block = HirBlock();
    exits.add(block);
    block.end(HirExit(block.add(HirConst(code))));
    return block;
  }

  HirValue test(HirTypeTest test) =>
      handler.add(HirIsInstance(test, handler.parameters[0]));
  final isB = test(_isB), isA = test(_isA);
  final more = HirBlock();
  handler.end(HirBranch(isB, HirEdge(exit(2)), HirEdge(more)));
  more.end(HirBranch(isA, HirEdge(exit(3)), HirEdge(exit(4))));
  final main = HirFunction('main', const [])
    ..define([entry, normal, handler, more, ...exits]);
  return HirModule(
    main,
    [main, ...others, ?stackOverflow, ?outOfMemory, ?allocate, ?raise],
    classes: [_a, _b, _c],
    tests: {
      _isA: {_a, _b},
      _isB: {_b},
    },
    globals: globals,
    stackOverflow: stackOverflow,
    outOfMemory: outOfMemory,
    allocate: allocate,
    raise: raise,
  );
}

HirFunction _throwing(HirClass class_, {String name = 'throwing'}) =>
    _function(name, [], (block) {
      final object = block.add(HirNew(class_));
      return HirThrow(object, block.add(HirNew(_c)));
    });

void main() {
  test('throws are caught, and their classes known', () {
    for (final (class_, code) in [(_b, 2), (_a, 3), (_c, 4)]) {
      final thrower = _throwing(class_);
      final module = _module((_) => HirCall(thrower, []), [thrower]);
      expect(HirInterpreter(module).run(), code);
      expect(runLowered(module), code);
    }
  });

  test('calls through classes and creations may throw', () {
    final selector = HirSelector('f', [], .integer);
    final thrower = _function('f', [.reference], (block) {
      return HirThrow(block.parameters.single, block.add(HirNew(_c)));
    }, result: .integer);
    final main = _module((block) {
      return HirVirtualCall(selector, block.add(HirNew(_b)), []);
    }, [thrower]);
    final module = HirModule(
      main.main,
      main.functions,
      classes: main.classes,
      tests: main.tests,
      dispatch: {
        selector: {_b: thrower},
      },
    );
    expect(HirInterpreter(module).run(), 2);
    expect(runLowered(module), 2);
    // A creation gives an object that knows its class.
    final entry = HirBlock(), made = HirBlock([.reference, .integer]);
    final handler = HirBlock([.reference, .reference]);
    entry.end(
      HirInvoke(
        HirNew(_b),
        HirEdge(made, [entry.add(HirConst(30))]),
        HirEdge(handler),
      ),
    );
    handler.end(HirReturn());
    final [object, thirty] = made.parameters;
    final yes = HirBlock(), no = HirBlock();
    made.end(
      HirBranch(
        made.add(HirIsInstance(_isB, object)),
        HirEdge(yes),
        HirEdge(no),
      ),
    );
    yes.end(HirExit(thirty));
    no.end(HirReturn());
    final creating = HirFunction('main', const [])
      ..define([entry, made, handler, yes, no]);
    final created = HirModule(
      creating,
      [creating],
      classes: [_a, _b],
      tests: {
        _isB: {_b},
      },
    );
    expect(HirInterpreter(created).run(), 30);
    expect(runLowered(created), 30);
  });

  test('variables are divisors and shifts', () {
    for (final a in integers) {
      for (final b in integers) {
        for (final operator in HirIntOperator.values) {
          final expected = integerResult(operator, a, b);
          if (expected == null) continue;
          final f = _function('f', [.integer, .integer], (block) {
            return HirReturn(
              block.add(
                HirIntBinary(
                  operator,
                  block.parameters[0],
                  block.parameters[1],
                ),
              ),
            );
          }, result: .integer);
          final module = body((block) {
            return HirExit(
              block.add(
                HirCall(f, [block.add(HirConst(a)), block.add(HirConst(b))]),
              ),
            );
          }, [f]);
          expect(
            runLowered(module),
            expected,
            reason: '$a ${operator.symbol} $b',
          );
        }
      }
    }
  });

  test('doubles become ints, up to the largest', () {
    for (final value in [
      ...doubles.where((value) => value.isFinite),
      -0.9,
      1.9,
      9223372036854774784.0,
      9223372036854775808.0,
      -9223372036854775808.0,
      -9223372036854777856.0,
      1e300,
      -1e300,
    ]) {
      final module = body((block) {
        final constant = block.add(HirConst(value));
        return HirExit(block.add(HirUnary(.floatToInt, constant)));
      });
      expect(runLowered(module), value.toInt(), reason: '$value');
    }
  });

  test('a program ends with what nothing catches', () {
    final thrower = _throwing(_b);
    final uncaught = _function('uncaught', [.reference], (block) {
      block
        ..add(HirWriteError('error é '))
        ..add(HirWriteError('b\n'));
      return HirReturn();
    });
    final module = body((block) {
      block
        ..add(HirPrint('out'))
        ..add(HirCall(thrower, []));
      return HirReturn();
    }, [thrower, uncaught]);
    final run = LoweredRun(
      HirModule(
        module.main,
        module.functions,
        classes: [_a, _b, _c],
        uncaught: uncaught,
      ),
    );
    expect(run.code, 255);
    expect(run.output, 'out\n');
    expect(run.errors, 'error é b\n');
  });

  test('single bytes are written to standard error', () {
    final module = body((block) {
      for (final byte in [0, 104, 255]) {
        block.add(HirMachine(.writeError, [block.add(HirConst(byte))]));
      }
      return HirReturn();
    });
    expect(LoweredRun(module).errorBytes, [0, 104, 255]);
  });

  group('the stack', () {
    final overflow = _throwing(_b, name: 'overflow');
    HirModule recursing({required bool checksStack}) {
      final f = HirFunction('f', const [], null, checksStack);
      final block = HirBlock()
        ..add(HirCall(f, []))
        ..end(HirReturn());
      f.define([block]);
      return _module((_) => HirCall(f, []), [f], stackOverflow: overflow);
    }

    test('overflows', () {
      expect(runLowered(recursing(checksStack: true)), 2);
    });

    test('is checked by functions that ask for it', () {
      bool checks(HirModule module, String name) =>
          lowerProgram(module).functions
              .firstWhere((function) => function.name.endsWith(name))
              .checksStack;
      for (final asks in [true, false]) {
        expect(checks(recursing(checksStack: asks), '.f'), asks);
      }
      for (final name in ['overflow', stackOverflowSymbol, entrySymbol]) {
        expect(checks(recursing(checksStack: true), name), isFalse);
      }
      final plain = _throwing(_a);
      final module = _module((_) => HirCall(plain, []), [plain]);
      expect(checks(module, 'throwing'), isFalse);
      expect(lowerProgram(module).statics, isEmpty);
    });

    test('has a limit a part of it above its end', () {
      final module = lowerProgram(recursing(checksStack: true));
      final start = module.functions.firstWhere((f) => f.name == entrySymbol);
      expect(
        start.blocks.first.instructions
            .whereType<Call>()
            .map((call) => call.symbol)
            .take(3),
        [
          'pthread_self',
          'pthread_get_stackaddr_np',
          'pthread_get_stacksize_np',
        ],
      );
      expect(start.blocks.first.instructions.whereType<Store>(), hasLength(1));
      final [size, ...] = start.blocks.first.instructions
          .whereType<ConstInt>()
          .map((constant) => constant.value)
          .toList();
      expect(size, 128 << 10);
    });
  });

  test('a program without memory throws', () {
    HirFunction allocate(int address) => _function(
      'allocate',
      [.integer],
      (block) => HirReturn(block.add(HirConst(address))),
      result: .integer,
    );
    LirFunction made(HirFunction? outOfMemory) => lowerProgram(
      _module(
        (_) => HirNew(_a),
        [],
        allocate: allocate(0),
        outOfMemory: outOfMemory,
      ),
    ).functions.firstWhere((function) => function.name == allocateSymbol);
    expect(made(null).blocks, hasLength(1));
    final outOfMemory = _throwing(_b, name: 'full');
    final lowered = lowerProgram(
      _module(
        (_) => HirNew(_a),
        [],
        allocate: allocate(0),
        outOfMemory: outOfMemory,
      ),
    );
    expect(
      () => LirInterpreter(lowered).call(allocateSymbol, [16]),
      throwsA(isA<LirException>()),
    );
  });

  test('machine code throws through the runtime', () {
    final raise = _function('raise', [.reference, .reference], (block) {
      block.add(HirMachine(.trap, []));
      return HirUnreachable();
    });
    final thrower = _throwing(_b);
    final module = lowerProgram(
      _module((_) => HirCall(thrower, []), [thrower], raise: raise),
    );
    expect(module.signatures[throwSymbol], LirSignature([.ref, .ref]));
  });

  test('resuming and finding handlers', () {
    final raise = _function('raise', [.reference, .reference], (block) {
      final [exception, trace] = block.parameters;
      final handlers = block.add(HirMachine(.handlers, []));
      block.add(HirMachine(.resume, [handlers, handlers, exception, trace]));
      return HirUnreachable();
    });
    final thrower = _throwing(_b);
    final module = lowerProgram(
      _module((_) => HirCall(thrower, []), [thrower], raise: raise),
    );
    final code = module.functions
        .firstWhere((function) => function.name.endsWith('.raise'))
        .blocks
        .single;
    expect((code.instructions.first as SymbolAddress).symbol, handlerSymbol);
    final resume = code.instructions.whereType<Resume>().single;
    expect([resume.exception, resume.trace], code.parameters);
    expect(code.terminator, isA<Unreachable>());
  });
}
