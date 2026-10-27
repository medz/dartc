import 'host.dart';
import 'source_uri.dart';

class SourcePackage {
  final String name;
  final String rootUri;
  final String packageUri;
  final int languageMajor;
  final int languageMinor;
  String? rootPath;
  String? packagePath;

  SourcePackage(
    this.name,
    this.rootUri,
    this.packageUri,
    this.languageMajor,
    this.languageMinor,
  );
}

class PackageConfig {
  final String path;
  final List<SourcePackage> packages;

  PackageConfig(this.path, this.packages);
}

class _PackageJson {
  final String path;
  final String text;
  int position = 0;

  _PackageJson(this.path, this.text);
}

Never _packageError(_PackageJson json, String message) {
  print(
    'dartc: ' +
        json.path +
        ': ' +
        message +
        ' at offset ' +
        json.position.toString(),
  );
  hostExit(1);
}

bool _jsonDigit(int value) => value >= 48 && value <= 57;

void _jsonSpace(_PackageJson json) {
  while (json.position < json.text.length) {
    var c = json.text.codeUnitAt(json.position);
    if (c != 32 && c != 9 && c != 10 && c != 13) return;
    json.position++;
  }
}

bool _jsonTake(_PackageJson json, int value) {
  if (json.position < json.text.length &&
      json.text.codeUnitAt(json.position) == value) {
    json.position++;
    return true;
  }
  return false;
}

void _jsonRequire(_PackageJson json, int value) {
  if (!_jsonTake(json, value)) _packageError(json, 'invalid JSON');
}

void _jsonUnits(List<int> units, String text, int start, int end) {
  while (start < end) {
    units.add(text.codeUnitAt(start));
    start++;
  }
}

int _jsonHex(_PackageJson json) {
  if (json.position == json.text.length)
    _packageError(json, 'incomplete JSON Unicode escape');
  var c = json.text.codeUnitAt(json.position++);
  if (_jsonDigit(c)) return c - 48;
  if (c >= 65 && c <= 70) return c - 55;
  if (c >= 97 && c <= 102) return c - 87;
  _packageError(json, 'invalid JSON Unicode escape');
}

String _jsonString(_PackageJson json, bool keep) {
  _jsonRequire(json, 34);
  var start = json.position;
  List<int>? units;
  while (json.position < json.text.length) {
    var c = json.text.codeUnitAt(json.position++);
    if (c == 34) {
      if (!keep) return '';
      if (units == null) return json.text.substring(start, json.position - 1);
      _jsonUnits(units, json.text, start, json.position - 1);
      return String.fromCharCodes(units);
    }
    if (c < 32) _packageError(json, 'unescaped JSON control character');
    if (c != 92) continue;
    if (keep) {
      units ??= <int>[];
      _jsonUnits(units, json.text, start, json.position - 1);
    }
    if (json.position == json.text.length)
      _packageError(json, 'incomplete JSON escape');
    c = json.text.codeUnitAt(json.position++);
    if (c == 117) {
      c =
          _jsonHex(json) * 4096 +
          _jsonHex(json) * 256 +
          _jsonHex(json) * 16 +
          _jsonHex(json);
    } else if (c == 98) {
      c = 8;
    } else if (c == 102) {
      c = 12;
    } else if (c == 110) {
      c = 10;
    } else if (c == 114) {
      c = 13;
    } else if (c == 116) {
      c = 9;
    } else if (c != 34 && c != 92 && c != 47) {
      _packageError(json, 'invalid JSON escape');
    }
    if (keep) units!.add(c);
    start = json.position;
  }
  _packageError(json, 'unterminated JSON string');
}

void _jsonDigits(_PackageJson json) {
  var start = json.position;
  while (json.position < json.text.length &&
      _jsonDigit(json.text.codeUnitAt(json.position))) {
    json.position++;
  }
  if (start == json.position) _packageError(json, 'invalid JSON number');
}

void _jsonNumber(_PackageJson json) {
  _jsonTake(json, 45);
  if (!_jsonTake(json, 48)) _jsonDigits(json);
  if (_jsonTake(json, 46)) _jsonDigits(json);
  if (_jsonTake(json, 101) || _jsonTake(json, 69)) {
    if (!_jsonTake(json, 43)) _jsonTake(json, 45);
    _jsonDigits(json);
  }
}

void _jsonLiteral(_PackageJson json, String literal) {
  var i = 0;
  while (i < literal.length) {
    _jsonRequire(json, literal.codeUnitAt(i));
    i++;
  }
}

void _jsonValue(_PackageJson json) {
  _jsonSpace(json);
  if (json.position == json.text.length)
    _packageError(json, 'missing JSON value');
  var c = json.text.codeUnitAt(json.position);
  if (c == 34) {
    _jsonString(json, false);
  } else if (_jsonTake(json, 123)) {
    _jsonSpace(json);
    if (_jsonTake(json, 125)) return;
    while (true) {
      _jsonString(json, false);
      _jsonSpace(json);
      _jsonRequire(json, 58);
      _jsonValue(json);
      _jsonSpace(json);
      if (_jsonTake(json, 125)) return;
      _jsonRequire(json, 44);
      _jsonSpace(json);
    }
  } else if (_jsonTake(json, 91)) {
    _jsonSpace(json);
    if (_jsonTake(json, 93)) return;
    while (true) {
      _jsonValue(json);
      _jsonSpace(json);
      if (_jsonTake(json, 93)) return;
      _jsonRequire(json, 44);
    }
  } else if (c == 116) {
    _jsonLiteral(json, 'true');
  } else if (c == 102) {
    _jsonLiteral(json, 'false');
  } else if (c == 110) {
    _jsonLiteral(json, 'null');
  } else {
    _jsonNumber(json);
  }
}

String _packageString(_PackageJson json, int offset, String name) {
  if (offset < 0) _packageError(json, 'missing ' + name);
  json.position = offset;
  if (json.text.codeUnitAt(offset) != 34)
    _packageError(json, name + ' must be a JSON string');
  return _jsonString(json, true);
}

int _packageVersionPart(_PackageJson json, String version, int start, int end) {
  if (start == end || end - start > 1 && version.codeUnitAt(start) == 48)
    _packageError(json, 'invalid languageVersion');
  var value = 0;
  while (start < end) {
    var c = version.codeUnitAt(start++);
    if (!_jsonDigit(c)) _packageError(json, 'invalid languageVersion');
    var digit = c - 48;
    if (value > 922337203685477580 || value == 922337203685477580 && digit > 7)
      _packageError(json, 'languageVersion number is too large');
    value = value * 10 + digit;
  }
  return value;
}

SourcePackage _packageEntry(_PackageJson json) {
  _jsonRequire(json, 123);
  var nameOffset = -1;
  var rootOffset = -1;
  var packageOffset = -1;
  var versionOffset = -1;
  _jsonSpace(json);
  if (!_jsonTake(json, 125)) {
    while (true) {
      var key = _jsonString(json, true);
      _jsonSpace(json);
      _jsonRequire(json, 58);
      _jsonSpace(json);
      if (key == 'name') nameOffset = json.position;
      if (key == 'rootUri') rootOffset = json.position;
      if (key == 'packageUri') packageOffset = json.position;
      if (key == 'languageVersion') versionOffset = json.position;
      _jsonValue(json);
      _jsonSpace(json);
      if (_jsonTake(json, 125)) break;
      _jsonRequire(json, 44);
      _jsonSpace(json);
    }
  }
  var end = json.position;
  var name = _packageString(json, nameOffset, 'name');
  if (!sourcePackageName(name)) _packageError(json, 'invalid package name');
  var root = _packageString(json, rootOffset, 'rootUri');
  var package = '';
  if (packageOffset >= 0)
    package = _packageString(json, packageOffset, 'packageUri');
  var major = -1;
  var minor = -1;
  if (versionOffset >= 0) {
    var version = _packageString(json, versionOffset, 'languageVersion');
    var dot = version.indexOf('.');
    if (dot < 0) _packageError(json, 'invalid languageVersion');
    major = _packageVersionPart(json, version, 0, dot);
    minor = _packageVersionPart(json, version, dot + 1, version.length);
  }
  json.position = end;
  return SourcePackage(name, root, package, major, minor);
}

PackageConfig parsePackageConfig(String path, String text) {
  var json = _PackageJson(path, text);
  if (text.isNotEmpty && text.codeUnitAt(0) == 65279) json.position = 1;
  _jsonSpace(json);
  _jsonRequire(json, 123);
  var versionOffset = -1;
  var packagesOffset = -1;
  _jsonSpace(json);
  if (!_jsonTake(json, 125)) {
    while (true) {
      var key = _jsonString(json, true);
      _jsonSpace(json);
      _jsonRequire(json, 58);
      _jsonSpace(json);
      if (key == 'configVersion') versionOffset = json.position;
      if (key == 'packages') packagesOffset = json.position;
      _jsonValue(json);
      _jsonSpace(json);
      if (_jsonTake(json, 125)) break;
      _jsonRequire(json, 44);
      _jsonSpace(json);
    }
  }
  _jsonSpace(json);
  if (json.position != text.length) _packageError(json, 'trailing JSON data');
  if (versionOffset < 0) _packageError(json, 'missing configVersion');
  json.position = versionOffset;
  _jsonValue(json);
  if (text.substring(versionOffset, json.position) != '2')
    _packageError(json, 'configVersion must be the JSON integer 2');
  if (packagesOffset < 0) _packageError(json, 'missing packages');
  json.position = packagesOffset;
  _jsonRequire(json, 91);
  var packages = <SourcePackage>[];
  _jsonSpace(json);
  if (!_jsonTake(json, 93)) {
    while (true) {
      var package = _packageEntry(json);
      var i = 0;
      while (i < packages.length) {
        if (packages[i].name == package.name)
          _packageError(json, 'duplicate package name ' + package.name);
        i++;
      }
      packages.add(package);
      _jsonSpace(json);
      if (_jsonTake(json, 93)) break;
      _jsonRequire(json, 44);
      _jsonSpace(json);
    }
  }
  return PackageConfig(path, packages);
}

Never packageConfigError(PackageConfig config, String message) {
  var location = '';
  if (config.path != '') location = config.path + ': ';
  print('dartc: ' + location + message);
  hostExit(1);
}

String _packageDirectory(String path) {
  if (path.endsWith('/')) return path;
  return path + '/';
}

void resolvePackageConfig(PackageConfig config, String configUri) {
  var i = 0;
  while (i < config.packages.length) {
    var package = config.packages[i];
    var root = package.rootUri;
    var library = package.packageUri;
    if (root.indexOf('?') >= 0 || root.indexOf('#') >= 0)
      packageConfigError(config, 'rootUri cannot have a query or fragment');
    if (sourceUriScheme(library) != '' ||
        library.startsWith('/') ||
        library.startsWith('\\') ||
        library.indexOf('?') >= 0 ||
        library.indexOf('#') >= 0)
      packageConfigError(config, 'packageUri must be a relative directory URI');
    var scheme = sourceUriScheme(root);
    if (scheme == '' || scheme == 'file') {
      var rootUri = _packageDirectory(sourceResolveFileUri(configUri, root));
      var libraryUri = _packageDirectory(
        sourceResolveFileUri(rootUri, library),
      );
      var rootPath = sourceUriPath('/', rootUri);
      var packagePath = sourceUriPath('/', libraryUri);
      if (!packagePath.startsWith(rootPath))
        packageConfigError(
          config,
          'packageUri escapes package root: ' + package.name,
        );
      package.rootPath = rootPath;
      package.packagePath = packagePath;
    }
    i++;
  }
  i = 0;
  while (i < config.packages.length) {
    var package = config.packages[i];
    var root = package.rootPath;
    var library = package.packagePath;
    if (root != null && library != null) {
      var j = 0;
      while (j < config.packages.length) {
        var other = config.packages[j];
        var nested = other.rootPath;
        if (j != i && nested != null) {
          if (root == nested)
            packageConfigError(config, 'duplicate package root: ' + root);
          if (nested.startsWith(root) &&
              (nested.startsWith(library) || library.startsWith(nested)))
            packageConfigError(
              config,
              'packageUri overlaps nested package: ' + package.name,
            );
        }
        j++;
      }
    }
    i++;
  }
}

SourcePackage? sourcePackageForFile(PackageConfig config, String path) {
  SourcePackage? owner;
  var length = 0;
  var i = 0;
  while (i < config.packages.length) {
    var package = config.packages[i];
    var root = package.rootPath;
    if (root != null && root.length > length && path.startsWith(root)) {
      owner = package;
      length = root.length;
    }
    i++;
  }
  return owner;
}

String resolvePackageUri(PackageConfig config, SourcePackageUri uri) {
  var i = 0;
  while (i < config.packages.length) {
    var package = config.packages[i];
    if (package.name == uri.name) {
      var directory = package.packagePath;
      if (directory == null)
        packageConfigError(
          config,
          'unsupported package root URI: ' + package.rootUri,
        );
      var path = sourceUriPath(directory, './' + uri.path);
      if (!path.startsWith(directory))
        packageConfigError(
          config,
          'package URI escapes package root: ' + uri.name + '/' + uri.path,
        );
      return path;
    }
    i++;
  }
  packageConfigError(config, 'unknown package: ' + uri.name);
}
