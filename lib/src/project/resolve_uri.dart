/// Resolves a source [reference] against [from], preserving its URI identity.
///
/// Relative references require an absolute [from]. Relative package references
/// keep the same package name. A `dart:core` library resolves relative references
/// below `dart:core/`. URI aliases are not resolved through the file system.
/// Invalid references throw [FormatException].
Uri resolveSourceUri(Uri reference, {Uri? from}) {
  if (reference.hasQuery || reference.hasFragment) {
    throw FormatException(
      'Source URIs cannot have a query or fragment.',
      reference,
    );
  }
  if (reference.hasScheme) return validateSourceUri(reference.normalizePath());
  if (from == null || !from.hasScheme) {
    throw FormatException(
      'A relative source URI requires an absolute base.',
      reference,
    );
  }
  var base = validateSourceUri(from);
  if (base.scheme == 'dart' && !base.path.contains('/')) {
    base = base.replace(path: '${base.path}/');
  }
  final resolved = validateSourceUri(base.resolveUri(reference));
  if (base.scheme == 'package' &&
      (resolved.scheme != 'package' ||
          packageName(resolved) != packageName(base))) {
    throw FormatException(
      'A relative URI cannot leave its package.',
      reference,
    );
  }
  return resolved;
}

Uri validateSourceUri(Uri uri) {
  if (!uri.hasScheme || uri.hasQuery || uri.hasFragment) {
    throw FormatException(
      'Expected an absolute source URI without a query or fragment.',
      uri,
    );
  }
  if (uri.scheme == 'package') packageName(uri);
  if (uri.scheme == 'dart' &&
      (uri.hasAuthority || uri.path.isEmpty || uri.path.startsWith('/'))) {
    throw FormatException('Invalid dart: URI.', uri);
  }
  return uri;
}

String packageName(Uri uri) {
  final slash = uri.path.indexOf('/');
  if (uri.hasAuthority || uri.hasQuery || uri.hasFragment || slash <= 0) {
    throw FormatException('Expected package:name/path.', uri);
  }
  final name = uri.path.substring(0, slash);
  if (!validPackageName(name)) {
    throw FormatException('Invalid package name.', uri);
  }
  return name;
}

bool validPackageName(String name) =>
    _packageName.hasMatch(name) && name.codeUnits.any((c) => c != 46);

final _packageName = RegExp(r"^[a-zA-Z0-9!$&'()*+,\-.;=@_~]+$");
