import 'package:dartc/source.dart';

import '../sources/file_source.dart';
import 'configuration.dart';

/// Finds the nearest `.dart_tool/package_config.json` above [entry].
///
/// A missing configuration returns `null`. Invalid configuration contents and
/// provider failures propagate, so an invalid nearer configuration cannot be
/// silently replaced by one in a parent directory.
Future<PackageConfiguration?> findPackageConfiguration(
  Uri entry, {
  SourceProvider readSource = readFileSource,
}) async {
  if (!entry.hasScheme || entry.scheme == 'package' || entry.scheme == 'dart') {
    throw ArgumentError.value(
      entry,
      'entry',
      'Expected an absolute source location.',
    );
  }
  var directory = entry.resolve('.');
  while (true) {
    final uri = directory.resolve('.dart_tool/package_config.json');
    final text = await readSource(uri);
    if (text != null) return PackageConfiguration.parse(text, uri: uri);
    if (directory.path.isEmpty) return null;
    final parent = directory.resolve('../');
    if (parent.path.length >= directory.path.length) return null;
    directory = parent;
  }
}
