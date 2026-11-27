import 'dart:typed_data';

import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';
import 'package:test/test.dart';

import '../hir/support.dart';
import 'support.dart';

final _n = HirField('n', .integer), _link = HirField('link', .reference);
final _d = HirField('d', .float), _b = HirField('b', .boolean);
final _base = HirClass('Base', null, [_n, _link]);
final _class = HirClass('C', _base, [_d, _b]);
final _inner = HirConstObject(_base, {_n: 5, _link: null});
final _outer = HirConstObject(_class, {
  _n: -6,
  _link: _inner,
  _d: 2.5,
  _b: true,
});
final _count = HirGlobal('count', .integer, 3);
final _object = HirGlobal('object', .reference, _outer);
final _half = HirGlobal('half', .float, 0.5);
final _yes = HirGlobal('yes', .boolean, true);
final _no = HirGlobal('no', .boolean, false);
final _none = HirGlobal('none', .reference, null);

HirFunction _allocate() {
  final block = HirBlock([.integer]);
  block.end(HirReturn(block.add(HirMachine(.mapMemory, block.parameters))));
  return HirFunction('allocate', [.integer], .integer)..define([block]);
}

HirModule _module(
  HirTerminator Function(HirBlock block) build, {
  HirFunction? allocate,
}) {
  final module = body(build, [?allocate]);
  return HirModule(
    module.main,
    module.functions,
    classes: [_base, _class],
    globals: [_count, _object, _half, _yes, _no, _none],
    allocate: allocate,
  );
}

void main() {
  /// Runs at both levels, which must agree that [build]'s value holds.
  void holds(String name, HirValue Function(HirBlock block) build) =>
      test(name, () {
        final module = _module((block) {
          final condition = build(block);
          final yes = HirBlock(), no = HirBlock();
          yes.end(HirExit(yes.add(HirConst(1))));
          no.end(HirExit(no.add(HirConst(0))));
          return HirBranch(condition, HirEdge(yes), HirEdge(no));
        });
        expect(HirInterpreter(module).run(), 1);
        expect(runLowered(module), 1);
      });

  HirValue equal(HirBlock block, HirValue value, Object constant) =>
      block.add(HirCompare(.equal, value, block.add(HirConst(constant))));

  HirValue all(HirBlock block, List<HirValue> conditions) =>
      conditions.reduce((a, b) => block.add(HirBoolBinary(.and, a, b)));

  holds('globals start with their values', (block) {
    final none = block.add(HirLoadGlobal(_none));
    final object = block.add(HirLoadGlobal(_object));
    return all(block, [
      equal(block, block.add(HirLoadGlobal(_count)), 3),
      equal(block, block.add(HirLoadGlobal(_half)), 0.5),
      block.add(HirLoadGlobal(_yes)),
      block.add(HirUnary(.not, block.add(HirLoadGlobal(_no)))),
      block.add(HirCompare(.equal, none, block.add(HirNull()))),
      block.add(HirCompare(.equal, object, block.add(HirStatic(_outer)))),
    ]);
  });

  holds('globals change', (block) {
    block
      ..add(HirStoreGlobal(_count, block.add(HirConst(40))))
      ..add(HirStoreGlobal(_half, block.add(HirConst(-1.5))))
      ..add(HirStoreGlobal(_none, block.add(HirLoadGlobal(_object))));
    final none = block.add(HirLoadGlobal(_none));
    return all(block, [
      equal(block, block.add(HirLoadGlobal(_count)), 40),
      equal(block, block.add(HirLoadGlobal(_half)), -1.5),
      block.add(HirCompare(.equal, none, block.add(HirStatic(_outer)))),
    ]);
  });

  holds('constants hold their fields', (block) {
    final outer = block.add(HirStatic(_outer));
    final link = block.add(HirLoad(_link, outer));
    final rest = block.add(HirLoad(_link, link));
    return all(block, [
      equal(block, block.add(HirLoad(_n, outer)), -6),
      equal(block, block.add(HirLoad(_d, outer)), 2.5),
      block.add(HirLoad(_b, outer)),
      block.add(HirCompare(.equal, link, block.add(HirStatic(_inner)))),
      equal(block, block.add(HirLoad(_n, link)), 5),
      block.add(HirCompare(.equal, rest, block.add(HirNull()))),
    ]);
  });

  test('each constant is stored once and cannot change', () {
    final module = lowerProgram(
      _module((block) {
        block
          ..add(HirStatic(_inner))
          ..add(HirStatic(_outer))
          ..add(HirStatic(_inner));
        return HirReturn();
      }),
    );
    final constants = module.statics.where((object) => !object.writable);
    expect([
      for (final object in constants)
        ByteData.sublistView(object.bytes).getUint32(0, .little),
    ], unorderedEquals([0, 1]));
    for (final object in constants) {
      // The second word tells the collector to leave it alone.
      expect(ByteData.sublistView(object.bytes).getUint32(4, .little), 4);
    }
    expect(module.statics.where((object) => object.writable), hasLength(1));
  });

  test('references among globals come first', () {
    final module = lowerProgram(_module((_) => HirReturn()));
    final globals = module.statics.singleWhere((object) => object.writable);
    expect(globals.bytes, hasLength(8 + 6 * 8));
    expect(globals.references.keys, [8]);
    final words = ByteData.sublistView(globals.bytes);
    expect(words.getInt64(16, .little), 0);
    expect([
      for (var at = 24; at < 56; at += 8) words.getInt64(at, .little),
    ], unorderedEquals([3, 0x3fe0000000000000, 1, 0]));
  });

  test('a program without any of this has no objects', () {
    final module = lowerProgram(body((_) => HirReturn()));
    expect(module.statics, isEmpty);
    expect(module.data, isEmpty);
  });

  test('the class table lists the references of each class', () {
    final module = lowerProgram(
      _module((_) => HirReturn(), allocate: _allocate()),
    );
    final table = module.data.singleWhere((data) => data.name == '.classes');
    final words = ByteData.sublistView(Uint8List.fromList(table.bytes));
    List<int> offsets(int class_) {
      final record = words.getUint32(class_ * 4, .little);
      return [
        for (var i = 0; i < words.getUint32(record, .little); i++)
          words.getUint32(record + 8 + i * 4, .little),
      ];
    }

    expect(offsets(0), [16]);
    // The kind is in the low bits, the size of the fields above bit 8.
    final kind = words.getUint32(words.getUint32(0, .little) + 4, .little);
    expect(kind & 127, 0);
    expect(kind >> 8, 24);
    expect(offsets(1), [16]);
  });

  test('allocation goes through the given function', () {
    final module = lowerProgram(
      _module((block) {
        block.add(HirNew(_base));
        return HirReturn();
      }, allocate: _allocate()),
    );
    expect(module.signatures['.allocate'], LirSignature([.i64], .i64));
  });

  group('machine operations', () {
    /// Runs [build] as the body of a function given the address of memory.
    Object? run(
      HirValue Function(HirBlock block, HirValue address) build, {
      Map<String, LirExternalBody> externals = const {},
      bool collectsAlways = false,
    }) {
      final inner = HirBlock([.integer]);
      inner.end(HirReturn(build(inner, inner.parameters.single)));
      final function = HirFunction('f', [.integer], .integer)..define([inner]);
      final module = HirModule(
        body((_) => HirReturn()).main,
        [],
        globals: [_count, _object, _none],
        classes: [_base, _class],
      );
      final main = body((_) => HirReturn(), [function]);
      final lowered = lowerProgram(
        HirModule(
          main.main,
          main.functions,
          globals: module.globals,
          classes: module.classes,
          allocate: function,
        ),
        collectsAlways: collectsAlways,
      );
      final interpreter = LirInterpreter(lowered, externals: externals);
      final bytes = Uint8List.fromList([
        for (var i = 0; i < 32; i++) 0xf8 + i & 0xff,
      ]);
      // The function given as [HirModule.allocate] is called by its symbol.
      return interpreter.call('.allocate', [interpreter.memory.map(bytes)]);
    }

    HirValue at(HirBlock block, HirValue address, int offset) =>
        block.add(HirIntBinary(.add, address, block.add(HirConst(offset))));

    test('loads and stores', () {
      expect(
        run((b, a) => b.add(HirMachine(.load64, [at(b, a, 8)]))),
        0x0706050403020100,
      );
      expect(run((b, a) => b.add(HirMachine(.load32, [a]))), 0xfbfaf9f8);
      expect(
        run((b, a) => b.add(HirMachine(.load32Signed, [a]))),
        0xfbfaf9f8 - (1 << 32),
      );
      expect(
        run((b, a) {
          b.add(HirMachine(.store64, [a, b.add(HirConst(-5))]));
          return b.add(HirMachine(.load64, [a]));
        }),
        -5,
      );
      expect(
        run((b, a) {
          b.add(HirMachine(.store32, [at(b, a, 8), b.add(HirConst(-1))]));
          return b.add(HirMachine(.load64, [at(b, a, 8)]));
        }),
        0x07060504ffffffff,
      );
    });

    test('mapping memory', () {
      for (final (given, result) in [(0x5000, 0x5000), (-1, 0)]) {
        final calls = <List<Object?>>[];
        final found = run(
          (b, a) => b.add(HirMachine(.mapMemory, [b.add(HirConst(4096))])),
          externals: {
            'mmap': (_, arguments) {
              calls.add(arguments);
              return given;
            },
          },
        );
        expect(found, result);
        // Private, anonymous memory that can be read and written.
        expect(calls, [
          [0, 4096, 3, 0x1002, -1, 0],
        ]);
      }
      final calls = <List<Object?>>[];
      run(
        (b, a) {
          b.add(
            HirMachine(.unmapMemory, [
              b.add(HirConst(0x5000)),
              b.add(HirConst(64)),
            ]),
          );
          return a;
        },
        externals: {
          'munmap': (_, arguments) {
            calls.add(arguments);
            return 0;
          },
        },
      );
      expect(calls, [
        [0x5000, 64],
      ]);
    });

    test('tables and roots', () {
      expect(run((b, a) => b.add(HirMachine(.globalRootCount, []))), 2);
      expect(run((b, a) => b.add(HirMachine(.classTable, []))), isPositive);
      // Code, frames and objects have no addresses in the interpreter.
      for (final op in <HirMachineOp>[
        .codeStart,
        .stackMaps,
        .frameAddress,
        .globalRoots,
      ]) {
        expect(
          () => run((b, a) => b.add(HirMachine(op, []))),
          throwsA(isA<LirFault>()),
          reason: op.name,
        );
      }
    });

    test('addresses of code, stack maps and globals', () {
      for (final (op, symbol) in <(HirMachineOp, String)>[
        (.codeStart, textSymbol),
        (.stackMaps, stackMapSymbol),
        (.globalRoots, '.globals'),
      ]) {
        final block = HirBlock([.integer]);
        block.end(HirReturn(block.add(HirMachine(op, []))));
        final function = HirFunction('f', [.integer], .integer)
          ..define([block]);
        final main = body((_) => HirReturn(), [function]);
        final module = lowerProgram(
          HirModule(main.main, main.functions, allocate: function),
        );
        final code = module.functions
            .singleWhere((function) => function.name == '.allocate')
            .blocks
            .single
            .instructions;
        expect((code.first as SymbolAddress).symbol, symbol);
        if (op == .globalRoots) {
          // The header of the object comes first.
          final offset = code.whereType<ConstInt>().single;
          final sum = code.whereType<IntBinary>().single;
          expect((offset.value, sum.op), (8, IntOp.add));
        }
      }
    });

    test('collecting always is decided when compiling', () {
      for (final always in [true, false]) {
        final block = HirBlock([.integer]);
        final flag = block.add(HirMachine(.collectsAlways, []));
        final yes = HirBlock(), no = HirBlock();
        block.end(HirBranch(flag, HirEdge(yes), HirEdge(no)));
        yes.end(HirReturn(yes.add(HirConst(1))));
        no.end(HirReturn(no.add(HirConst(0))));
        final function = HirFunction('f', [.integer], .integer)
          ..define([block, yes, no]);
        final main = body((_) => HirReturn(), [function]);
        final lowered = lowerProgram(
          HirModule(main.main, main.functions, allocate: function),
          collectsAlways: always,
        );
        expect(LirInterpreter(lowered).call('.allocate', [0]), always ? 1 : 0);
      }
    });

    test('trapping ends the code', () {
      final block = HirBlock([.integer])..add(HirMachine(.trap, []));
      block.end(HirUnreachable());
      final function = HirFunction('f', [.integer], .integer)..define([block]);
      final main = body((_) => HirReturn(), [function]);
      final lowered = lowerProgram(
        HirModule(main.main, main.functions, allocate: function),
      );
      expect(
        () => LirInterpreter(lowered).call('.allocate', [0]),
        throwsA(isA<LirFault>()),
      );
    });
  });
}
