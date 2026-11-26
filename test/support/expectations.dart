import 'dart:convert';

/// What a program is expected to do, as comments in its source tell:
///
/// ```dart
/// print(1 + 1); // expect: 2
/// // exit: 3
/// // stderr: Unhandled exception:
/// // long
/// external int x; // error 14: Not supported yet: external variables.
/// ```
///
/// Each `expect` is the next line of the output, each `stderr` that of the
/// errors. They can be on lines of their own, where they are about the line
/// before. A text in quotes is as in JSON.
/// Programs marked `long` take too long to collect before every allocation.
/// An `error` is where a program is refused, with its column. Without one, it
/// is refused elsewhere, such as in the SDK.
/// A line `// official: …` tells why the official Dart does something else,
/// which the language does not mean; the other comments are written by hand.
///
/// `tool/expect.dart` writes and checks them with the official Dart, apart from
/// the errors.
final class const Expectations({
  final List<String> output = const [],
  final List<String> errors = const [],
  final int exitCode = 0,
  final bool isLong = false,

  /// Where it is refused, and why.
  final List<String> problems = const [],

  /// Why it is refused elsewhere.
  final String? elsewhere,

  /// Whether there are any, apart from `long`.
  final bool isTold = false,

  /// Why the official Dart does something else, if it does.
  final String? official,
}) {
  static final _official = RegExp(r'^// official: (.*)$', multiLine: true);

  static final _comment = RegExp(
    r'// (?:(expect|stderr|exit):(?: (.*))?|(long)|error( \d+)?: (.*))$',
  );

  factory of(String source) {
    final output = <String>[], errors = <String>[], problems = <String>[];
    var exitCode = 0, isLong = false, isTold = false, code = 0;
    String? elsewhere;
    for (final (i, line) in const LineSplitter().convert(source).indexed) {
      final found = _comment.firstMatch(line);
      if (line.substring(0, found?.start).trim().isNotEmpty) code = i + 1;
      if (found == null) continue;
      if (found[3] == null) isTold = true;
      final text = found[2] ?? '';
      switch (found[1]) {
        case 'expect':
          output.add(_read(text));
        case 'stderr':
          errors.add(_read(text));
        case 'exit':
          exitCode = int.parse(text);
        default:
          final problem = found[5];
          if (problem == null) {
            isLong = true;
          } else if (found[4] case final column?) {
            problems.add('main.dart:$code:${column.trim()}: $problem');
          } else {
            elsewhere = problem;
          }
      }
    }
    return Expectations(
      output: output,
      errors: errors,
      exitCode: exitCode,
      isLong: isLong,
      problems: problems,
      elsewhere: elsewhere,
      isTold: isTold,
      official: _official.firstMatch(source)?[1],
    );
  }

  bool get isRefused => problems.isNotEmpty || elsewhere != null;

  /// [source] without comments that tell what it does when it runs.
  static String removedFrom(String source) {
    final kept = <String>[];
    for (final line in const LineSplitter().convert(source)) {
      final found = _comment.firstMatch(line);
      if (found == null || found[1] == null) {
        kept.add(line);
        continue;
      }
      final before = line.substring(0, found.start).trimRight();
      if (before.isNotEmpty) kept.add(before);
    }
    return '${kept.join('\n')}\n';
  }

  static String _read(String text) =>
      text.startsWith('"') ? jsonDecode(text) as String : text;

  /// The comment for a line of the output, or of the errors.
  static String expect(String text) => '// expect:${_written(text)}';
  static String stderr(String text) => '// stderr:${_written(text)}';

  static String _written(String text) {
    if (text.isEmpty) return '';
    final isPlain =
        !text.startsWith('"') &&
        text.trim() == text &&
        text.codeUnits.every((unit) => unit >= 0x20 && unit != 0x7f);
    return ' ${isPlain ? text : jsonEncode(text)}';
  }

  /// The lines of [text], of which the last has to end, too.
  static List<String> linesOf(String text) {
    if (text.isEmpty) return const [];
    final lines = text.split('\n');
    if (lines.removeLast().isNotEmpty) {
      throw FormatException('The last line does not end', text, text.length);
    }
    return lines;
  }
}
