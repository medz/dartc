import 'dart:ffi';

import 'package:test/test.dart';

import '../../sdk/runtime/process.dart';

void main() {
  test(
    'process main selects positional arity and preserves remaining defaults',
    () {
      final events = <Object?>[];
      runMain(0, 0, () => events.add('zero'));
      runMain(0, 0, ({int value = 73}) => events.add(value));
      runMain(0, 0, (Iterable<String> args) => events.add(args.isEmpty));
      runMain(0, 0, ([List<String>? args]) => events.add(args?.isEmpty));
      runMain(0, 0, (List<String> args, Object? message, [int value = 91]) {
        events.addAll([args.isEmpty, message, value]);
      });
      expect(events, ['zero', 73, true, true, true, null, 91]);
    },
  );

  test('main without positional parameters does not decode unused argv', () {
    final library = DynamicLibrary.process();
    final allocate = library
        .lookupFunction<
          Pointer<Void> Function(Size),
          Pointer<Void> Function(int)
        >('malloc');
    final release = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final storage = allocate(2 * sizeOf<Pointer>() + 2);
    expect(storage, isNot(nullptr));
    try {
      final argv = storage.cast<Pointer<Uint8>>();
      final text = storage.cast<Uint8>() + 2 * sizeOf<Pointer>();
      text[0] = 0xff;
      text[1] = 0;
      argv[0] = nullptr;
      argv[1] = text;
      var calls = 0;
      runMain(2, argv.address, () => calls++);
      runMain(2, argv.address, ({int value = 73}) => calls += value);
      expect(calls, 74);
      expect(
        () => runMain(2, argv.address, (List<String> arguments) {}),
        throwsFormatException,
      );
    } finally {
      release(storage);
    }
  });

  test(
    'main arguments have fixed writable storage and callback errors propagate',
    () {
      runMain(0, 0, (List<String> args) {
        expect(args, isEmpty);
        expect(() => args.add('extra'), throwsUnsupportedError);
      });
      final failure = StateError('main');
      expect(
        () => runMain(0, 0, (List<String> args) => throw failure),
        throwsA(same(failure)),
      );
      expect(
        () => runMain(0, 0, (List<String> args, String message) {}),
        throwsA(isA<TypeError>()),
      );
    },
  );
}
