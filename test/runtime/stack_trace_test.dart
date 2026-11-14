import 'package:test/test.dart';

import '../../sdk/runtime/stack_trace.dart';

void main() {
  test(
    'logical frames keep order and numbering across physical and async frames',
    () {
      final inner = CapturedStackTrace(
        1,
        null,
        'leaf (part.dart:3:4)\nwrapper (main.dart:5:6)',
      );
      final outer = CapturedStackTrace(2, inner, 'root (main.dart:7:8)');
      final trace = outer.followedBy('resume (main.dart:9:10)\nentry');
      const expected =
          '#0 leaf (part.dart:3:4)\n#1 wrapper (main.dart:5:6)\n'
          '#2 root (main.dart:7:8)\n<asynchronous suspension>\n'
          '#3 resume (main.dart:9:10)\n#4 entry';
      expect(trace.toString(), expected);
      expect(trace.toString(), expected);
      expect(
        CapturedStackTrace(16, trace, null).toString(),
        '$expected\n#5 0x10',
      );
      expect(
        inner.toString(),
        '#0 leaf (part.dart:3:4)\n#1 wrapper (main.dart:5:6)',
      );
    },
  );
}
