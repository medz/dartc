import '../lib/src/diagnostic.dart';
import '../lib/src/driver/packages.dart';
import '../lib/src/host.dart';
import '../lib/src/source.dart';
import '../lib/src/source_uri.dart';
import '../lib/src/utf8.dart';

void _literal(StringBuffer output, String value) {
  const digits = '0123456789abcdef';
  output.write("'");
  var start = 0;
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    String? escaped = switch (unit) {
      39 => r"\'",
      92 => r'\\',
      36 => r'\$',
      10 => r'\n',
      13 => r'\r',
      _ => null,
    };
    if (escaped == null && (unit < 32 || unit == 0x2028 || unit == 0x2029)) {
      escaped =
          r'\u' +
          digits[(unit >> 12) & 15] +
          digits[(unit >> 8) & 15] +
          digits[(unit >> 4) & 15] +
          digits[unit & 15];
    }
    if (escaped != null) {
      output.write(value.substring(start, i));
      output.write(escaped);
      start = i + 1;
    }
  }
  output.write(value.substring(start));
  output.write("'");
}

void _bundle(List<String> args) {
  if (args.length != 2) {
    print('Usage: bundle_compiler <checkout> <entry.dart>');
    hostExit(64);
  }
  final cwd = hostCurrentDirectory();
  var root = sourceInputUri(cwd, args[0]);
  if (!root.endsWith('/')) root += '/';
  final runtime = sourceResolveFileUri(root, 'lib/src/runtime.dart');
  final config = compilerPackages(runtime, cwd, null);
  final files = <SourceFile>[];
  // Include the dependency closure for each supported source platform.
  for (final target in const <int>[0, 1]) {
    final program = collectSources(runtime, runtime, config, target);
    for (final file in program.files) {
      var found = false;
      for (final previous in files) {
        if (previous.uri == file.uri) found = true;
      }
      if (!found) files.add(file);
    }
  }
  final output = StringBuffer(
    '// Generated from the compiler source closure.\n',
  );
  for (final relative in const <String>[
    'lib/src/driver/command.dart',
    'lib/src/source_bundle.dart',
  ]) {
    output.write('import ');
    _literal(output, sourceResolveFileUri(root, relative));
    output.writeln(';');
  }
  output.write('const sources = SourceBundle(');
  _literal(output, runtime);
  output.writeln(', <BundledSource>[');
  for (final file in files) {
    final fileUri = sourceFileUri(file.path);
    if (!fileUri.startsWith(root))
      throw Diagnostic(
        'dartc: bundled dependency is outside the checkout: ' + file.path,
      );
    output.write('  BundledSource(');
    _literal(output, file.uri);
    output.write(', ');
    _literal(output, hostReadSource(file.path));
    output.writeln('),');
  }
  output.write('  BundledSource(');
  _literal(output, 'package:dartc/export.dart');
  output.write(', ');
  _literal(
    output,
    hostReadSource(
      sourceUriPath('/', sourceResolveFileUri(root, 'lib/export.dart')),
    ),
  );
  output.writeln('),\n]);');
  output.writeln('void main(List<String> args) => runCompiler(args, sources);');
  hostWrite(args[1], encodeUtf8(output.toString()));
  print(args[1]);
}

void main(List<String> args) {
  try {
    _bundle(args);
  } on Diagnostic catch (error) {
    print(error.message);
    hostExit(1);
  }
}
