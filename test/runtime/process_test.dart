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
