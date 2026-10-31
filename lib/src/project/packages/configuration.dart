import 'dart:convert';

import 'package:dartc/parser.dart';

import '../resolve_uri.dart';

/// A package's source roots and optional default Dart language version.
final class Package._(
  /// The package URI's first path component.
  final String name,

  /// The absolute directory containing the package's files.
  final Uri root,

  /// The absolute directory exposed through `package:` URIs.
  final Uri packageRoot,

  /// The default language version, or `null` to use the loader's default.
  final LanguageVersion? languageVersion,
);

/// An immutable version 2 Dart package configuration.
final class PackageConfiguration {
  /// Creates a configuration without packages.
  const PackageConfiguration.empty() : packages = const {}, _roots = const {};

  PackageConfiguration._(Map<String, Package> packages)
    : packages = Map.unmodifiable(packages),
      _roots = {for (final package in packages.values) package.root: package};

  /// Parses JSON, resolving package roots relative to the configuration [uri].
  ///
  /// Unrecognized metadata is ignored. Invalid formats, names, versions or
  /// overlapping package roots throw [FormatException].
  factory PackageConfiguration.parse(String text, {required Uri uri}) {
    if (!uri.hasScheme ||
        uri.scheme == 'package' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        'The configuration location must be an absolute non-package URI.',
        uri,
      );
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?> ||
        decoded['configVersion'] is! int ||
        decoded['configVersion'] != 2 ||
        decoded['packages'] is! List<Object?>) {
      throw FormatException(
        'Expected a version 2 package configuration.',
        text,
      );
    }
    final packages = <String, Package>{};
    final base = uri.path.endsWith('/') ? uri : uri.resolve('.');
    for (final entry in decoded['packages'] as List<Object?>) {
      if (entry is! Map<String, Object?> ||
          entry['name'] is! String ||
          entry['rootUri'] is! String) {
        throw FormatException(
          'Each package requires name and rootUri strings.',
          text,
        );
      }
      final name = entry['name'] as String;
      if (!validPackageName(name) || packages.containsKey(name)) {
        throw FormatException(
          'Invalid or duplicate package name: $name.',
          text,
        );
      }
      final root = _directory(base.resolve(entry['rootUri'] as String));
      final relative = entry['packageUri'];
      if (entry.containsKey('packageUri') && relative is! String) {
        throw FormatException('packageUri must be a string.', text);
      }
      final exposed = relative is String ? Uri.parse(relative) : Uri();
      if (exposed.hasScheme ||
          exposed.hasAuthority ||
          exposed.path.startsWith('/')) {
        throw FormatException('packageUri must be relative to rootUri.', text);
      }
      final packageRoot = _directory(root.resolveUri(exposed));
      if (!packageRoot.toString().startsWith(root.toString())) {
        throw FormatException('packageUri cannot leave rootUri.', text);
      }
      LanguageVersion? version;
      if (entry.containsKey('languageVersion')) {
        final value = entry['languageVersion'];
        if (value is! String || !_version.hasMatch(value)) {
          throw FormatException(
            'Expected a major.minor languageVersion.',
            text,
          );
        }
        final components = value.split('.');
        final major = int.tryParse(components[0]);
        final minor = int.tryParse(components[1]);
        if (major == null ||
            minor == null ||
            major > 0x7fffffff ||
            minor > 0x7fffffff) {
          throw FormatException(
            'Language version component is out of range.',
            text,
          );
        }
        version = LanguageVersion(major, minor);
      }
      packages[name] = Package._(name, root, packageRoot, version);
    }
    final ordered = packages.values.toList()
      ..sort((a, b) => a.root.toString().compareTo(b.root.toString()));
    final parents = <Package>[];
    for (final package in ordered) {
      final root = package.root.toString();
      while (parents.isNotEmpty &&
          !root.startsWith(parents.last.root.toString())) {
        parents.removeLast();
      }
      if (parents.lastOrNull case final parent?) {
        if (package.root == parent.root ||
            root.startsWith(parent.packageRoot.toString()) ||
            parent.packageRoot.toString().startsWith(root)) {
          throw FormatException(
            'Conflicting package roots: ${parent.name} and ${package.name}.',
            text,
          );
        }
      }
      parents.add(package);
    }
    return PackageConfiguration._(packages);
  }

  /// The packages indexed by name, in configuration order.
  final Map<String, Package> packages;
  final Map<Uri, Package> _roots;

  /// Resolves a `package:` URI to its source location.
  ///
  /// Unknown packages return `null`; malformed URIs throw [FormatException].
  Uri? resolve(Uri uri) {
    if (uri.scheme != 'package') {
      throw FormatException('Expected a package: URI.', uri);
    }
    final name = packageName(uri);
    final package = packages[name];
    if (package == null) return null;
    return package.packageRoot.resolveUri(
      Uri(path: uri.path.substring(name.length + 1)),
    );
  }

  /// Finds the package owning [uri], including files outside its `lib/` directory.
  Package? packageFor(Uri uri) {
    if (uri.scheme == 'package') return packages[packageName(uri)];
    if (!uri.hasScheme) return null;
    var directory = uri.resolve('.');
    while (true) {
      if (_roots[directory] case final package?) return package;
      if (directory.path.isEmpty) return null;
      final parent = directory.resolve('../');
      if (parent.path.length >= directory.path.length) return null;
      directory = parent;
    }
  }
}

final _version = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');

Uri _directory(Uri uri) {
  if (!uri.hasScheme ||
      uri.scheme == 'package' ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw FormatException(
      'Expected an absolute non-package directory URI.',
      uri,
    );
  }
  return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
}
