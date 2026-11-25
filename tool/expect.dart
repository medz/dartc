import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../test/support/expectations.dart';

const _usage = '''
Usage: dart run tool/expect.dart [--update] [file or directory ...]

Runs the programs in test/programs with the official Dart, and tells which do
not do what their comments say. With --update, writes the comments.''';

/// What a line of the output was printed by: the line of code in `main`, if it
/// is known.
typedef _Printed = ({String text, int? line});

/// What the official Dart does with a program.
typedef _Run = ({List<_Printed> output, List<String> errors, int exitCode});

Future<void> main(List<String> arguments) async {
  final updates = arguments.contains('--update');
  final paths = arguments.where((a) => a != '--update').toList();
  if (paths.any((path) => path.startsWith('-'))) {
    stderr.writeln(_usage);
    exit(64);
  }
  final files = [
    for (final path in paths.isEmpty ? ['test/programs'] : paths)
      ..._programsIn(path),
  ];
  final directory = Directory.systemTemp.createTempSync('dartc-expect-');
  final wrong = <String>[];
  try {
    final pending = files.iterator;
    Future<void> work(int worker) async {
      while (pending.moveNext()) {
        final file = pending.current;
        final place = Directory('${directory.path}/$worker')..createSync();
        if (!await _handle(file, place, updates: updates)) wrong.add(file.path);
      }
    }

    await Future.wait([
      for (var i = 0; i < Platform.numberOfProcessors; i++) work(i),
    ]);
  } finally {
    directory.deleteSync(recursive: true);
  }
  for (final path in wrong..sort()) {
    stdout.writeln('${updates ? 'Updated' : 'Wrong'}: $path');
  }
  stdout.writeln('${files.length} programs, ${wrong.length} of them differ.');
  if (wrong.isNotEmpty && !updates) exitCode = 1;
}

/// The programs in the file or directory [path], each by the file with its
/// `main`.
List<File> _programsIn(String path) {
  if (FileSystemEntity.isFileSync(path)) return [File(path)];
  final main = File('$path/main.dart');
  if (main.existsSync()) return [main];
  final found = Directory(path).listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [for (final entity in found) ..._programsIn(entity.path)];
}

/// Checks [file], or writes its comments. Gives whether it was right.
Future<bool> _handle(
  File file,
  Directory place, {
  required bool updates,
}) async {
  final source = file.readAsStringSync();
  final expected = Expectations.of(source);
  // The official Dart does not know what dartc refuses.
  if (expected.isRefused) return true;
  final plain = Expectations.removedFrom(source);
  for (final old in place.listSync()) {
    old.deleteSync();
  }
  if (file.uri.pathSegments.last == 'main.dart') {
    for (final other in file.parent.listSync().whereType<File>()) {
      other.copySync('${place.path}/${other.uri.pathSegments.last}');
    }
  }
  final run = await _runOfficially(plain, place, seeksLines: updates);
  final isRight =
      expected.isTold &&
      _same([for (final line in run.output) line.text], expected.output) &&
      _same(run.errors, expected.errors) &&
      run.exitCode == expected.exitCode;
  if (updates && !isRight) file.writeAsStringSync(_annotated(plain, run));
  return isRight;
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);

Future<_Run> _runOfficially(
  String source,
  Directory place, {
  required bool seeksLines,
}) async {
  final dart = Platform.resolvedExecutable;
  final main = File('${place.path}/main.dart')..writeAsStringSync(source);
  final result = await Process.run(dart, ['run', main.path]);
  // Stack traces, which follow, are not compared.
  final errors = Expectations.linesOf('${result.stderr}')
      .takeWhile((line) => !line.startsWith('#0 '))
      .toList();
  final lines = Expectations.linesOf('${result.stdout}');
  final known = seeksLines ? await _seekLines(dart, place) : null;
  final agrees =
      known != null && _same([for (final line in known) line.text], lines);
  return (
    output: agrees
        ? known
        : [for (final text in lines) (text: text, line: null)],
    errors: errors,
    exitCode: result.exitCode,
  );
}

/// What the program prints, with the lines in `main` that it comes from.
Future<List<_Printed>> _seekLines(String dart, Directory place) async {
  final wrapper = File('${place.path}/wrapper.dart')
    ..writeAsStringSync(r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'main.dart' as program;

void main(List<String> arguments) {
  final Function run = program.main;
  runZonedGuarded(
    () => run is void Function() ? run() : run(arguments),
    (error, trace) {},
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, text) {
        final frames = RegExp(r'^#\d+\s+main \(.*[/:]main\.dart:(\d+)', multiLine: true)
            .allMatches('${StackTrace.current}');
        final line = frames.isEmpty ? null : int.parse(frames.last[1]!);
        stdout.writeln('\u0001' + jsonEncode([text, line]));
      },
    ),
  );
}
''');
  final result = await Process.run(dart, ['run', wrapper.path]);
  return [
    for (final line in const LineSplitter().convert('${result.stdout}'))
      if (line.startsWith('\u0001'))
        if (jsonDecode(line.substring(1)) case [
          final String text,
          final int? at,
        ])
          for (final part in text.split('\n')) (text: part, line: at),
  ];
}

/// [source] with comments that tell about [run], each after the statement of
/// `main` that it comes from.
String _annotated(String source, _Run run) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final lines = const LineSplitter().convert(source);
  final ends = <(int, int)>[
    for (final statement in _statementsOf(parsed.unit))
      (
        parsed.lineInfo.getLocation(statement.offset).lineNumber,
        parsed.lineInfo.getLocation(statement.end).lineNumber,
      ),
  ];
  // Output comes in the order of the statements, so that what is done later is
  // told after what came before.
  final after = <int, List<String>>{};
  var latest = 0;
  for (final (:text, :line) in run.output) {
    if (line != null) {
      final at = ends.indexWhere((e) => e.$1 <= line && line <= e.$2);
      if (at > latest) latest = at;
    }
    final end = ends.isEmpty ? lines.length : ends[latest].$2;
    (after[end] ??= []).add(Expectations.expect(text));
  }
  (after[lines.length] ??= []).addAll([
    for (final line in run.errors) Expectations.stderr(line),
    if (run.exitCode != 0 || run.output.isEmpty && run.errors.isEmpty)
      '// exit: ${run.exitCode}',
  ]);
  return [
    for (final (i, line) in lines.indexed)
      ..._withComments(line, after[i + 1] ?? const []),
    '',
  ].join('\n');
}

List<String> _withComments(String line, List<String> comments) {
  final indent = line.substring(0, line.length - line.trimLeft().length);
  return switch (comments) {
    [final only] when line.endsWith(';') && line.length < 78 => ['$line $only'],
    _ => [line, for (final comment in comments) '$indent$comment'],
  };
}

List<Statement> _statementsOf(CompilationUnit unit) {
  for (final declaration in unit.declarations) {
    if (declaration is! FunctionDeclaration) continue;
    if (declaration.name.lexeme != 'main') continue;
    final body = declaration.functionExpression.body;
    if (body is BlockFunctionBody) return body.block.statements;
  }
  return const [];
}
