import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _head = HirField('head', .reference);
final _list = HirClass('List', null, [_head], .references);
final _bytes = HirClass('Bytes', null, [], .bytes);
final _plain = HirClass('Plain', null, []);

HirModule _module(
  HirTerminator Function(HirBlock block) build, [
  List<HirClass>? classes,
]) {
  final module = body(build);
  return HirModule(
    module.main,
    module.functions,
    classes: classes ?? [_plain, _list, _bytes],
  );
}

/// What exiting with the value of [build] gives.
int? _run(HirValue Function(HirBlock block) build) =>
    HirInterpreter(_module((block) => HirExit(build(block)))).run();

/// Whether what [build] gives holds.
bool _holds(HirValue Function(HirBlock block) build) {
  final yes = HirBlock(), no = HirBlock();
  yes.end(HirExit(yes.add(HirConst(1))));
  no.end(HirExit(no.add(HirConst(0))));
  final entry = HirBlock();
  entry.end(HirBranch(build(entry), HirEdge(yes), HirEdge(no)));
  final main = HirFunction('main', const [])..define([entry, yes, no]);
  final module = HirModule(main, [main], classes: [_plain, _list, _bytes]);
  return HirInterpreter(module).run() == 1;
}

void main() {
  HirValue number(HirBlock block, int value) => block.add(HirConst(value));

  group('arrays', () {
    test('have a length', () {
      expect(
        _run((block) {
          final array = block.add(HirNewArray(_list, number(block, 7)));
          return block.add(HirLength(array));
        }),
        7,
      );
    });

    test('hold references, which are null at first', () {
      expect(
        _holds((block) {
          final array = block.add(HirNewArray(_list, number(block, 2)));
          final one = number(block, 1), zero = number(block, 0);
          block.add(HirStoreElement(.reference, array, one, array));
          final own = block.add(HirLoadElement(.reference, array, one));
          final none = block.add(HirLoadElement(.reference, array, zero));
          final same = block.add(HirCompare(.equal, own, array));
          final isNull = block.add(
            HirCompare(.equal, none, block.add(HirNull())),
          );
          return block.add(HirBoolBinary(.and, same, isNull));
        }),
        isTrue,
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
      test('hold numbers as ${element.name}', () {
        expect(
          _run((block) {
            final array = block.add(HirNewArray(_bytes, number(block, 16)));
            final at = number(block, 3);
            block.add(
              HirStoreElement(element, array, at, number(block, given)),
            );
            return block.add(HirLoadElement(element, array, at));
          }),
          read,
        );
      });
    }

    test('hold doubles, rounded to what there is room for', () {
      for (final (element, read) in [
        (HirElement.float64, 0.1),
        (HirElement.float32, 0.10000000149011612),
      ]) {
        expect(
          _holds((block) {
            final array = block.add(HirNewArray(_bytes, number(block, 16)));
            final at = number(block, 1);
            final value = block.add(HirConst(0.1));
            block.add(HirStoreElement(element, array, at, value));
            final found = block.add(HirLoadElement(element, array, at));
            return block.add(
              HirCompare(.equal, found, block.add(HirConst(read))),
            );
          }),
          isTrue,
        );
      }
    });

    test('can be constant', () {
      final inner = HirConstObject(_bytes, const {}, [1, 2, 250]);
      final outer = HirConstObject(_list, {_head: null}, [null, inner]);
      expect(
        _run((block) {
          final array = block.add(HirStatic(outer));
          final found = block.add(
            HirLoadElement(.reference, array, number(block, 1)),
          );
          return block.add(HirLoadElement(.uint8, found, number(block, 2)));
        }),
        250,
      );
      expect(
        () => _run((block) {
          final array = block.add(HirStatic(inner)), zero = number(block, 0);
          block.add(HirStoreElement(.uint8, array, zero, zero));
          return zero;
        }),
        throwsStateError,
      );
    });

    test('have no elements outside', () {
      for (final index in [-1, 2]) {
        expect(
          () => _run((block) {
            final array = block.add(HirNewArray(_list, number(block, 2)));
            block.add(HirLoadElement(.reference, array, number(block, index)));
            return number(block, 0);
          }),
          throwsRangeError,
        );
      }
    });

    test('are no other objects', () {
      expect(
        () => _run((block) {
          return block.add(HirLength(block.add(HirNew(_plain))));
        }),
        throwsStateError,
      );
    });
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
        final array = block.add(HirNewArray(_list, number(block, 1)));
        return block.add(HirMachine(.classNumber, [array]));
      }),
      1,
    );
  });

  test('objects have places of their own', () {
    expect(
      _holds((block) {
        final a = block.add(HirNew(_plain)), b = block.add(HirNew(_plain));
        final [first, second, again] = [
          for (final object in [a, b, a])
            block.add(HirMachine(.addressOf, [object])),
        ];
        final differ = block.add(HirCompare(.notEqual, first, second));
        final stay = block.add(HirCompare(.equal, first, again));
        return block.add(HirBoolBinary(.and, differ, stay));
      }),
      isTrue,
    );
  });

  test('doubles have bits and roots', () {
    expect(
      _holds((block) {
        final bits = block.add(HirUnary(.floatBits, block.add(HirConst(1.0))));
        final same = block.add(
          HirCompare(.equal, bits, number(block, 0x3ff0000000000000)),
        );
        final nine = block.add(
          HirUnary(.bitsFloat, number(block, 0x4022000000000000)),
        );
        final root = block.add(HirUnary(.squareRoot, nine));
        final isThree = block.add(
          HirCompare(.equal, root, block.add(HirConst(3.0))),
        );
        return block.add(HirBoolBinary(.and, same, isThree));
      }),
      isTrue,
    );
  });

  test('doubles are written and read', () {
    for (final (value, digits) in [(0.1, 17), (123.5, 2), (5e-324, 30)]) {
      final text = formatExactly(value, digits);
      expect(
        _holds((block) {
          final buffer = block.add(
            HirMachine(.mapMemory, [number(block, 4096)]),
          );
          final constant = block.add(HirConst(value));
          block.add(
            HirMachine(.formatDouble, [
              constant,
              number(block, digits),
              buffer,
            ]),
          );
          final found = block.add(HirMachine(.parseDouble, [buffer]));
          return block.add(
            HirCompare(.equal, found, block.add(HirConst(double.parse(text)))),
          );
        }),
        isTrue,
      );
    }
    expect(formatExactly(0.5, 30), '5.${'0' * 29}e-1');
    expect(formatExactly(0.1, 25), '1.000000000000000055511151e-1');
  });

  test('prints', () {
    final text = printHir(
      _module((block) {
        final array = block.add(HirNewArray(_bytes, number(block, 3)));
        final at = block.add(HirLength(array));
        final value = block.add(HirLoadElement(.int16, array, at));
        block
          ..add(HirStoreElement(.uint8, array, at, value))
          ..add(HirClassNumber(_list))
          ..add(HirStatic(HirConstObject(_bytes, const {}, [1, 2])));
        return HirReturn();
      }),
    );
    expect(text, contains('class List of references { reference head; }'));
    expect(text, contains('v1 = new Bytes[v0]\n'));
    expect(text, contains('v2 = v1.length\n'));
    expect(text, contains('v3 = v1[int16 v2]\n'));
    expect(text, contains('  v1[uint8 v2] = v3\n'));
    expect(text, contains('v4 = number List\n'));
    expect(text, contains('v5 = const Bytes([1, 2])\n'));
  });

  group('rejects', () {
    void rejects(String message, HirModule Function() build) => test(
      message,
      () {
        expect(
          () => verifyHir(build()),
          throwsA(isA<HirError>().having((e) => e.message, 'message', message)),
        );
      },
    );

    HirModule using(void Function(HirBlock block) add) => _module((block) {
      add(block);
      return HirReturn();
    });

    rejects('main: unlisted class Bytes', () {
      return _module((block) {
        block.add(HirNewArray(_bytes, number(block, 1)));
        return HirReturn();
      }, [_list]);
    });
    rejects('main: Plain has no elements', () {
      return using((block) {
        block.add(HirNewArray(_plain, number(block, 1)));
      });
    });
    rejects('main: Bytes has elements', () {
      return using((block) => block.add(HirNew(_bytes)));
    });
    rejects('main: length: expected int, found bool', () {
      return using((block) {
        block.add(HirNewArray(_bytes, block.add(HirConst(true))));
      });
    });
    rejects('main: array: expected reference, found int', () {
      return using((block) => block.add(HirLength(number(block, 1))));
    });
    rejects('main: index: expected int, found reference', () {
      return using((block) {
        final none = block.add(HirNull());
        block.add(HirLoadElement(.uint8, none, none));
      });
    });
    rejects('main: element: expected double, found int', () {
      return using((block) {
        final none = block.add(HirNull()), zero = number(block, 0);
        block.add(HirStoreElement(.float64, none, zero, zero));
      });
    });
    rejects('class Sub extends an array', () {
      return _module((_) => HirReturn(), [_bytes, HirClass('Sub', _bytes, [])]);
    });
    rejects('array Wide has several fields', () {
      final fields = [HirField('a', .integer), HirField('b', .integer)];
      return _module((_) => HirReturn(), [
        HirClass('Wide', null, fields, .bytes),
      ]);
    });
    for (final (target, elements) in [
      (_bytes, [256]),
      (_bytes, [-1]),
      (_bytes, [null]),
      (_bytes, null),
      (_list, [1]),
      (_list, null),
      (_plain, <Object?>[]),
    ]) {
      test('a constant ${target.name} with $elements', () {
        final constant = HirConstObject(target, {
          for (final field in target.fields) field: null,
        }, elements);
        expect(
          () => verifyHir(using((block) => block.add(HirStatic(constant)))),
          throwsA(
            isA<HirError>().having(
              (e) => e.message,
              'message',
              'constant ${target.name} has wrong elements',
            ),
          ),
        );
      });
    }
  });
}
