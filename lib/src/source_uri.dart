import 'diagnostic.dart';

Never _sourceUriError(String reference, String message) {
  throw Diagnostic('URI: ' + message + ': ' + reference, exitCode: 65);
}

// Raw POSIX paths keep %, #, ? and backslashes as file-name characters.
String sourcePath(String path) {
  if (path.indexOf('\u0000') >= 0) _sourceUriError(path, 'NUL in file path');
  var parts = <String>[];
  var absolute = path.startsWith('/');
  var start = 0;
  while (start < path.length) {
    var end = path.indexOf('/', start);
    if (end < 0) end = path.length;
    var part = path.substring(start, end);
    if (part != '' && part != '.') {
      if (part == '..' && parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (part != '..' || !absolute) {
        parts.add(part);
      }
    }
    start = end + 1;
  }
  var result = '';
  if (absolute) result = '/';
  var i = 0;
  while (i < parts.length) {
    if (i > 0) result = result + '/';
    result = result + parts[i];
    i++;
  }
  if (result == '') return '.';
  return result;
}

String _sourceUriSlashes(String reference) {
  if (reference.indexOf('\\') < 0) return reference;
  var codes = <int>[];
  var i = 0;
  while (i < reference.length) {
    var code = reference.codeUnitAt(i);
    if (code == 92) code = 47;
    codes.add(code);
    i++;
  }
  return String.fromCharCodes(codes);
}

bool _sourceUriLetter(int code) {
  return code >= 65 && code <= 90 || code >= 97 && code <= 122;
}

int _sourceUriSchemeEnd(String reference) {
  var i = 0;
  while (i < reference.length) {
    var code = reference.codeUnitAt(i);
    if (code == 47 || code == 63 || code == 35) return -1;
    if (code == 58) {
      if (i == 0 || !_sourceUriLetter(reference.codeUnitAt(0)))
        _sourceUriError(reference, 'invalid URI scheme');
      var n = 1;
      while (n < i) {
        var c = reference.codeUnitAt(n);
        if (!_sourceUriLetter(c) &&
            !(c >= 48 && c <= 57) &&
            c != 43 &&
            c != 45 &&
            c != 46)
          _sourceUriError(reference, 'invalid URI scheme');
        n++;
      }
      return i;
    }
    i++;
  }
  return -1;
}

String _sourceUriScheme(String text, int end) {
  var codes = <int>[];
  var i = 0;
  while (i < end) {
    var code = text.codeUnitAt(i);
    if (code >= 65 && code <= 90) code += 32;
    codes.add(code);
    i++;
  }
  return String.fromCharCodes(codes);
}

String sourceUriScheme(String reference) {
  var text = _sourceUriSlashes(reference);
  var end = _sourceUriSchemeEnd(text);
  if (end < 0) return '';
  return _sourceUriScheme(text, end);
}

int _sourceUriHex(int code) {
  if (code >= 48 && code <= 57) return code - 48;
  if (code >= 65 && code <= 70) return code - 55;
  if (code >= 97 && code <= 102) return code - 87;
  return -1;
}

int _sourceUriByte(String text, int at) {
  if (at + 2 >= text.length || text.codeUnitAt(at) != 37) return -1;
  var high = _sourceUriHex(text.codeUnitAt(at + 1));
  var low = _sourceUriHex(text.codeUnitAt(at + 2));
  if (high < 0 || low < 0) return -1;
  return high * 16 + low;
}

String _sourceUriDecode(String text, String reference) {
  if (text.indexOf('%') < 0) return text;
  var codes = <int>[];
  var i = 0;
  while (i < text.length) {
    var byte = _sourceUriByte(text, i);
    if (byte < 0) {
      // Uri.parse treats an incomplete/invalid escape as a literal percent.
      codes.add(text.codeUnitAt(i));
      i++;
    } else if (byte < 128) {
      if (byte == 0) _sourceUriError(reference, 'NUL in file URI');
      if (byte == 47) _sourceUriError(reference, 'encoded slash in file URI');
      codes.add(byte);
      i += 3;
    } else {
      var count = 0;
      var minimum = 0;
      var value = 0;
      if (byte >= 194 && byte <= 223) {
        count = 1;
        minimum = 128;
        value = byte & 31;
      } else if (byte >= 224 && byte <= 239) {
        count = 2;
        minimum = 2048;
        value = byte & 15;
      } else if (byte >= 240 && byte <= 244) {
        count = 3;
        minimum = 65536;
        value = byte & 7;
      } else {
        _sourceUriError(reference, 'invalid UTF-8 in file URI');
      }
      i += 3;
      var n = 0;
      while (n < count) {
        var next = _sourceUriByte(text, i);
        if (next < 128 || next > 191)
          _sourceUriError(reference, 'invalid UTF-8 in file URI');
        value = (value << 6) | (next & 63);
        i += 3;
        n++;
      }
      if (value < minimum ||
          value > 0x10ffff ||
          value >= 0xd800 && value <= 0xdfff)
        _sourceUriError(reference, 'invalid UTF-8 in file URI');
      if (value > 65535) {
        value -= 65536;
        codes.add(0xd800 + (value >> 10));
        codes.add(0xdc00 + (value & 1023));
      } else {
        codes.add(value);
      }
    }
  }
  return String.fromCharCodes(codes);
}

bool _sourceUriUnreserved(int code) {
  return _sourceUriLetter(code) ||
      code >= 48 && code <= 57 ||
      code == 45 ||
      code == 46 ||
      code == 95 ||
      code == 126;
}

String _sourceUriEscape(int byte) {
  var hex = '0123456789ABCDEF';
  return '%' +
      hex.substring(byte >> 4, (byte >> 4) + 1) +
      hex.substring(byte & 15, (byte & 15) + 1);
}

String _sourceUriCanonicalPath(String text, bool raw) {
  String? result;
  var i = 0;
  while (i < text.length) {
    var start = i;
    var code = text.codeUnitAt(i++);
    String? replacement;
    if (!raw && code == 37 && _sourceUriByte(text, start) >= 0) {
      var byte = _sourceUriByte(text, start);
      i = start + 3;
      if (_sourceUriUnreserved(byte))
        replacement = String.fromCharCodes(<int>[byte]);
      else
        replacement = _sourceUriEscape(byte);
    } else if (code >= 128) {
      if (code >= 0xd800 &&
          code <= 0xdbff &&
          i < text.length &&
          text.codeUnitAt(i) >= 0xdc00 &&
          text.codeUnitAt(i) <= 0xdfff) {
        code = 65536 + ((code - 0xd800) << 10) + text.codeUnitAt(i++) - 0xdc00;
      } else if (code >= 0xd800 && code <= 0xdfff) {
        code = 0xfffd;
      }
      if (code < 2048)
        replacement = _sourceUriEscape(192 | (code >> 6));
      else if (code < 65536)
        replacement =
            _sourceUriEscape(224 | (code >> 12)) +
            _sourceUriEscape(128 | ((code >> 6) & 63));
      else
        replacement =
            _sourceUriEscape(240 | (code >> 18)) +
            _sourceUriEscape(128 | ((code >> 12) & 63)) +
            _sourceUriEscape(128 | ((code >> 6) & 63));
      replacement += _sourceUriEscape(128 | (code & 63));
    } else if (!_sourceUriUnreserved(code) &&
        code != 47 &&
        code != 58 &&
        code != 64 &&
        code != 33 &&
        code != 36 &&
        code != 38 &&
        code != 39 &&
        code != 40 &&
        code != 41 &&
        code != 42 &&
        code != 43 &&
        code != 44 &&
        code != 59 &&
        code != 61) {
      if (code == 0) _sourceUriError(text, 'NUL in file path');
      replacement = _sourceUriEscape(code);
    }
    if (replacement != null) {
      result ??= text.substring(0, start);
      result += replacement;
    } else if (result != null) {
      result += text.substring(start, i);
    }
  }
  return result ?? text;
}

// Keep empty segments: URI identity distinguishes dir//file from dir/file.
String _sourceUriNormalizePath(String path, bool rooted) {
  var absolute = path.startsWith('/');
  var start = 0;
  if (absolute) start = 1;
  var parts = <String>[];
  var directory = path.endsWith('/');
  while (start < path.length) {
    var end = path.indexOf('/', start);
    if (end < 0) end = path.length;
    var part = path.substring(start, end);
    if (end == path.length && (part == '.' || part == '..')) directory = true;
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..')
        parts.removeLast();
      else if (!rooted && !absolute)
        parts.add(part);
    } else if (part != '.') {
      parts.add(part);
    }
    start = end + 1;
  }
  var result = '';
  if (absolute) result = '/';
  var i = 0;
  while (i < parts.length) {
    if (i > 0) result += '/';
    result += parts[i];
    i++;
  }
  if (directory && parts.isNotEmpty) result += '/';
  return result;
}

String _sourceUriRelativePath(String text) {
  var path = _sourceUriNormalizePath(
    _sourceUriCanonicalPath(text, false),
    false,
  );
  var end = path.indexOf('/');
  if (end < 0) end = path.length;
  // Removing leading ./ can expose a colon as a scheme delimiter.
  var colon = path.indexOf(':');
  if (colon < 0 || colon >= end) return path;
  var result = '';
  var i = 0;
  while (i < end) {
    var code = path.codeUnitAt(i);
    if (code == 58)
      result += '%3A';
    else
      result += path.substring(i, i + 1);
    i++;
  }
  return result + path.substring(end);
}

String _sourceFilePath(String reference) {
  var text = _sourceUriSlashes(reference);
  var schemeEnd = _sourceUriSchemeEnd(text);
  if (schemeEnd >= 0) {
    if (_sourceUriScheme(text, schemeEnd) != 'file')
      _sourceUriError(reference, 'unsupported URI scheme');
    text = text.substring(schemeEnd + 1);
  }
  if (text.indexOf('?') >= 0 || text.indexOf('#') >= 0)
    _sourceUriError(reference, 'file URI cannot have a query or fragment');
  var absolute = schemeEnd >= 0 || text.startsWith('//');
  if (text.startsWith('//')) {
    var end = text.indexOf('/', 2);
    if (end < 0) end = text.length;
    if (end != 2)
      _sourceUriError(reference, 'file URI authority is unsupported');
    text = text.substring(end);
  }
  if (absolute && !text.startsWith('/')) text = '/' + text;
  return text;
}

String sourceFileUri(String rawAbsolutePath) {
  if (!rawAbsolutePath.startsWith('/'))
    _sourceUriError(rawAbsolutePath, 'expected absolute file path');
  return 'file://' +
      _sourceUriNormalizePath(
        _sourceUriCanonicalPath(rawAbsolutePath, true),
        true,
      );
}

String sourceResolveFileUri(String baseFileUri, String reference) {
  if (sourceUriScheme(baseFileUri) != 'file')
    _sourceUriError(baseFileUri, 'expected file URI base');
  var base = _sourceFilePath(baseFileUri);
  var path = _sourceFilePath(reference);
  if (path == '')
    path = base;
  else if (path.startsWith('/'))
    path = _sourceUriCanonicalPath(path, false);
  else
    path =
        base.substring(0, base.lastIndexOf('/') + 1) +
        _sourceUriRelativePath(path);
  return 'file://' + _sourceUriNormalizePath(path, true);
}

// Decode only for I/O. Canonical URI strings, not OS paths, own library identity.
String sourceUriPath(String baseFilePath, String reference) {
  var uri = sourceResolveFileUri(sourceFileUri(baseFilePath), reference);
  var path = _sourceUriDecode(uri.substring(7), reference);
  var directory = path.endsWith('/');
  path = sourcePath(path);
  if (directory && path != '/') path += '/';
  return path;
}

// Package names use URI path-segment characters, not pub's identifier policy.
bool sourcePackageName(String name) {
  var nonDot = false;
  var i = 0;
  while (i < name.length) {
    var code = name.codeUnitAt(i++);
    if (code == 46) continue;
    nonDot = true;
    if (_sourceUriLetter(code) || code >= 48 && code <= 57) continue;
    if (code == 45 ||
        code == 95 ||
        code == 126 ||
        code == 33 ||
        code == 36 ||
        code == 38 ||
        code == 39 ||
        code == 40 ||
        code == 41 ||
        code == 42 ||
        code == 43 ||
        code == 44 ||
        code == 59 ||
        code == 61 ||
        code == 64)
      continue;
    return false;
  }
  return nonDot;
}

class SourcePackageUri {
  final String name;
  final String path;

  SourcePackageUri(this.name, this.path);
}

SourcePackageUri sourcePackageUri(String reference) {
  var text = _sourceUriSlashes(reference);
  var schemeEnd = _sourceUriSchemeEnd(text);
  if (schemeEnd < 0 || _sourceUriScheme(text, schemeEnd) != 'package')
    _sourceUriError(reference, 'expected package URI');
  text = text.substring(schemeEnd + 1);
  if (text.startsWith('//'))
    _sourceUriError(reference, 'package URI cannot have an authority');
  if (text.indexOf('?') >= 0 || text.indexOf('#') >= 0)
    _sourceUriError(reference, 'package URI cannot have a query or fragment');
  var slash = text.indexOf('/');
  if (slash <= 0) _sourceUriError(reference, 'package URI requires name/path');
  var name = _sourceUriDecode(text.substring(0, slash), reference);
  if (!sourcePackageName(name))
    _sourceUriError(reference, 'invalid package name');
  var path = text.substring(slash + 1);
  if (path.startsWith('/'))
    _sourceUriError(reference, 'package path escapes its root');
  return SourcePackageUri(name, _sourcePackagePath(path, reference, false));
}

String _sourcePackagePath(String path, String reference, bool clamp) {
  var result = _sourceUriNormalizePath(
    _sourceUriCanonicalPath(path, false),
    clamp,
  );
  if (result.startsWith('/') || result == '..' || result.startsWith('../'))
    _sourceUriError(reference, 'package path escapes its root');
  return result;
}

// Relative package references keep their package name even for /absolute paths.
SourcePackageUri sourcePackageRelative(SourcePackageUri base, String relative) {
  var text = _sourceUriSlashes(relative);
  if (_sourceUriSchemeEnd(text) >= 0)
    _sourceUriError(relative, 'expected relative package reference');
  if (text.startsWith('//'))
    _sourceUriError(relative, 'package URI cannot have an authority');
  if (text.indexOf('?') >= 0 || text.indexOf('#') >= 0)
    _sourceUriError(relative, 'package URI cannot have a query or fragment');
  if (text == '') return base;
  text = _sourceUriRelativePath(text);
  if (text.startsWith('/'))
    text = text.substring(1);
  else
    text = base.path.substring(0, base.path.lastIndexOf('/') + 1) + text;
  return SourcePackageUri(base.name, _sourcePackagePath(text, relative, true));
}

String sourceInputUri(String cwd, String argument) {
  if (argument.length >= 5 &&
      (argument.codeUnitAt(0) | 32) == 102 &&
      (argument.codeUnitAt(1) | 32) == 105 &&
      (argument.codeUnitAt(2) | 32) == 108 &&
      (argument.codeUnitAt(3) | 32) == 101 &&
      argument.codeUnitAt(4) == 58) {
    var base = cwd;
    if (!base.endsWith('/')) base += '/';
    return sourceResolveFileUri(sourceFileUri(base), argument);
  }
  var path = argument;
  if (!path.startsWith('/')) path = cwd + '/' + path;
  return sourceFileUri(path);
}
