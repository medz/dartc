// Reads regular expressions.

/// Reads a regular expression.
final class _RegExpParser {
  final String _source;
  final bool _isMultiLine, _isFolded, _isUnicode, _isDotAll;
  int _at = 0;

  /// The groups before here, and all.
  int _groups = 0;
  int groupCount = 0;
  final names = <String, int>{};

  /// Whether what is read is looked for behind.
  bool _isBackward = false;

  _RegExpParser(
    this._source,
    this._isMultiLine,
    this._isFolded,
    this._isUnicode,
    this._isDotAll,
  );

  static const _digits = [48, 57];
  static const _words = [48, 57, 65, 90, 95, 95, 97, 122];
  static const _spaces = [
    9, 13, 32, 32, 0xa0, 0xa0, 0x1680, 0x1680, 0x2000, 0x200a, //
    0x2028, 0x2029, 0x202f, 0x202f, 0x205f, 0x205f, 0x3000, 0x3000, //
    0xfeff, 0xfeff,
  ];

  _Matcher parse() {
    _findGroups();
    final result = _either();
    if (_at < _source.length) _fail('Unmatched )');
    return result;
  }

  Never _fail(String message) => throw FormatException(message, _source);

  bool get _isDone => _at >= _source.length;
  int get _here => _isDone ? -1 : _source.codeUnitAt(_at);

  bool _takes(String text) {
    if (!_source.startsWith(text, _at)) return false;
    _at += text.length;
    return true;
  }

  /// Counts the groups, as they can be referred to before they are read.
  void _findGroups() {
    var isInClass = false, index = 0;
    for (var i = 0; i < _source.length; i++) {
      switch (_source[i]) {
        case '\\':
          i++;
        case '[':
          isInClass = true;
        case ']':
          isInClass = false;
        case '(':
          if (isInClass) break;
          final isNamed =
              _source.startsWith('?<', i + 1) &&
              !_source.startsWith('?<=', i + 1) &&
              !_source.startsWith('?<!', i + 1);
          if (_source.startsWith('?', i + 1) && !isNamed) break;
          index++;
          if (!isNamed) break;
          final end = _source.indexOf('>', i);
          if (end < 0) _fail('Invalid capture group name');
          final name = _source.substring(i + 3, end);
          if (name.isEmpty) _fail('Invalid capture group name');
          if (names.containsKey(name)) _fail('Duplicate capture group name');
          names[name] = index;
      }
    }
    groupCount = index;
  }

  _Matcher _either() {
    final options = [_sequence()];
    while (_takes('|')) {
      options.add(_sequence());
    }
    return options.length == 1 ? options[0] : _EitherMatcher(options);
  }

  _Matcher _sequence() {
    final parts = <_Matcher>[];
    while (!_isDone && _here != 124 && _here != 41) {
      parts.add(_term());
    }
    if (parts.length == 1) return parts[0];
    return _SequenceMatcher(_isBackward ? parts.reversed.toList() : parts);
  }

  _Matcher _term() {
    if (_takes('^')) return _EdgeMatcher(false, _isMultiLine);
    if (_takes(r'$')) return _EdgeMatcher(true, _isMultiLine);
    if (_takes(r'\b')) return const _WordMatcher(false);
    if (_takes(r'\B')) return const _WordMatcher(true);
    if (_takes('(?<=')) return _look(isBehind: true, isNegative: false);
    if (_takes('(?<!')) return _look(isBehind: true, isNegative: true);
    final groups = _groups;
    final _Matcher atom;
    if (_takes('(?=')) {
      atom = _look(isBehind: false, isNegative: false);
      if (_isUnicode) return atom;
    } else if (_takes('(?!')) {
      atom = _look(isBehind: false, isNegative: true);
      if (_isUnicode) return atom;
    } else {
      atom = _atom();
    }
    return _repeated(atom, groups + 1);
  }

  _Matcher _look({required bool isBehind, required bool isNegative}) {
    final before = _isBackward;
    _isBackward = isBehind;
    final part = _inGroup();
    _isBackward = before;
    return _LookMatcher(part, isNegative);
  }

  _Matcher _inGroup() {
    final result = _either();
    if (!_takes(')')) _fail('Unterminated group');
    return result;
  }

  _Matcher _repeated(_Matcher atom, int firstGroup) {
    var least = 0, most = -1;
    if (_takes('*')) {
      // As often as it is there.
    } else if (_takes('+')) {
      least = 1;
    } else if (_takes('?')) {
      most = 1;
    } else {
      final found = _here == 123 ? _bounds() : null;
      if (found == null) return atom;
      least = found[0];
      most = found[1];
      if (most >= 0 && most < least) {
        _fail('numbers out of order in {} quantifier');
      }
    }
    final isGreedy = !_takes('?');
    return _RepeatMatcher(
      atom,
      least,
      most,
      isGreedy,
      firstGroup,
      _groups + 1,
    );
  }

  /// Reads `{least,most}`, if it is here.
  List<int>? _bounds() {
    final start = _at++;
    final least = _number();
    var most = least;
    if (least != null && _takes(',')) {
      most = _here == 125 ? -1 : _number();
    }
    if (least == null || most == null || !_takes('}')) {
      _at = start;
      if (_isUnicode) _fail('Incomplete quantifier');
      return null;
    }
    return [least, most];
  }

  int? _number() {
    final start = _at;
    var result = 0;
    while (_here >= 48 && _here <= 57) {
      // Nothing is as long.
      if (result < 1 << 40) result = result * 10 + _here - 48;
      _at++;
    }
    return _at == start ? null : result;
  }

  _Matcher _atom() {
    final unit = _here;
    switch (unit) {
      case 46:
        _at++;
        return _AnyMatcher(_isDotAll, _isUnicode, _isBackward);
      case 40:
        return _group();
      case 91:
        return _class();
      case 92:
        _at++;
        return _escape();
      case 42:
      case 43:
      case 63:
        _fail('Nothing to repeat');
      case 123:
        if (_isUnicode) _fail('Nothing to repeat');
        if (_bounds() != null) _fail('Nothing to repeat');
      case 93:
      case 125:
        if (_isUnicode) _fail('Lone quantifier brackets');
    }
    return _character(_next());
  }

  /// Takes a character.
  int _next() {
    final unit = _source.codeUnitAt(_at++);
    if (_isUnicode && unit & 0xfc00 == 0xd800 && !_isDone) {
      final trail = _here;
      if (trail & 0xfc00 == 0xdc00) {
        _at++;
        return ((unit - 0xd7c0) << 10) + (trail & 0x3ff);
      }
    }
    return unit;
  }

  _Matcher _character(int character) {
    if (!_isFolded) {
      return _CharacterMatcher(character, _isUnicode, _isBackward);
    }
    final folded = _foldCharacter(character);
    return _FoldedMatcher(folded, _isUnicode, _isBackward);
  }

  _Matcher _group() {
    _at++;
    if (_takes('?:')) return _inGroup();
    if (_takes('?<')) {
      _at = _source.indexOf('>', _at) + 1;
    } else if (_takes('?')) {
      _fail('Invalid group');
    }
    final index = ++_groups;
    return _GroupMatcher(_inGroup(), index, _isBackward);
  }

  _ClassMatcher _ranges(List<int> ranges, {bool isNegated = false}) =>
      _ClassMatcher(ranges, isNegated, _isFolded, _isUnicode, _isBackward);

  /// What is after a backslash.
  _Matcher _escape() {
    if (_isDone) _fail(r'\ at end of pattern');
    final ranges = _classEscape();
    if (ranges != null) return _ranges(ranges);
    final unit = _here;
    if (unit >= 49 && unit <= 57) {
      final start = _at;
      final index = _number()!;
      if (index <= groupCount) return _back([index]);
      if (_isUnicode) _fail('Invalid escape');
      _at = start;
      if (unit >= 56) return _character(_next());
    }
    if (unit == 107 && (names.isNotEmpty || _isUnicode)) {
      _at++;
      final end = _takes('<') ? _source.indexOf('>', _at) : -1;
      if (end < 0) _fail('Invalid named reference');
      final index = names[_source.substring(_at, end)];
      if (index == null) _fail('Invalid named capture referenced');
      _at = end + 1;
      return _back([index]);
    }
    return _character(_escaped());
  }

  _Matcher _back(List<int> indexes) =>
      _BackMatcher(indexes, _isFolded, _isBackward);

  /// The ranges of `\d` and the like, if that is here.
  List<int>? _classEscape() {
    final letter = _here | 32;
    final List<int> ranges;
    if (letter == 100) {
      ranges = _digits;
    } else if (letter == 119) {
      ranges = _words;
    } else if (letter == 115) {
      ranges = _spaces;
    } else {
      if (_isUnicode && letter == 112) {
        throw UnsupportedError('Unicode properties in regular expressions');
      }
      return null;
    }
    final isNegated = _here < 97;
    _at++;
    return isNegated ? _others(ranges) : ranges;
  }

  /// What is not in [ranges], which are in order.
  static List<int> _others(List<int> ranges) {
    final result = <int>[];
    var from = 0;
    for (var i = 0; i < ranges.length; i += 2) {
      if (ranges[i] > from) result.addAll([from, ranges[i] - 1]);
      from = ranges[i + 1] + 1;
    }
    result.addAll([from, 0x10ffff]);
    return result;
  }

  /// The character that is escaped here.
  int _escaped() {
    final unit = _next();
    switch (unit) {
      case 116:
        return 9;
      case 110:
        return 10;
      case 118:
        return 11;
      case 102:
        return 12;
      case 114:
        return 13;
      case 99:
        final letter = _here | 32;
        if (letter >= 97 && letter <= 122) {
          _at++;
          return letter & 31;
        }
        if (_isUnicode) _fail('Invalid unicode escape');
        _at--;
        return 92;
      case 120:
        return _hex(2) ?? unit;
      case 117:
        return _unicode() ?? unit;
    }
    return unit >= 48 && unit <= 55 ? _octal(unit) : unit;
  }

  int _octal(int first) {
    if (first == 48 && !(_here >= 48 && _here <= 57)) return 0;
    if (_isUnicode) _fail('Invalid decimal escape');
    var value = first - 48;
    while (_here >= 48 && _here <= 55 && value * 8 + _here - 48 < 256) {
      value = value * 8 + _here - 48;
      _at++;
    }
    return value;
  }

  int? _hex(int count) {
    var value = 0;
    if (_at + count <= _source.length) {
      for (var i = 0; i < count; i++) {
        final digit = int.tryParse(_source[_at + i], radix: 16);
        if (digit == null) {
          value = -1;
          break;
        }
        value = value * 16 + digit;
      }
      if (value >= 0) {
        _at += count;
        return value;
      }
    }
    if (_isUnicode) _fail('Invalid escape');
    return null;
  }

  int? _unicode() {
    if (_isUnicode && _takes('{')) {
      final end = _source.indexOf('}', _at);
      final value = end < 0
          ? null
          : int.tryParse(_source.substring(_at, end), radix: 16);
      if (value == null || value > 0x10ffff) _fail('Invalid Unicode escape');
      _at = end + 1;
      return value;
    }
    final lead = _hex(4);
    if (lead == null || !_isUnicode || lead & 0xfc00 != 0xd800) return lead;
    final start = _at;
    if (_takes(r'\u')) {
      final trail = _hex(4);
      if (trail != null && trail & 0xfc00 == 0xdc00) {
        return ((lead - 0xd7c0) << 10) + (trail & 0x3ff);
      }
    }
    _at = start;
    return lead;
  }

  _Matcher _class() {
    _at++;
    final isNegated = _takes('^');
    final ranges = <int>[];
    while (_here != 93) {
      if (_isDone) _fail('Unterminated character class');
      final first = _classPart();
      if (_here == 45 && _at + 1 < _source.length && _source[_at + 1] != ']') {
        _at++;
        final last = _classPart();
        if (first.length == 1 && last.length == 1) {
          if (first[0] > last[0]) _fail('Range out of order in character class');
          ranges.addAll([first[0], last[0]]);
          continue;
        }
        if (_isUnicode) _fail('Invalid character class');
        ranges.addAll([45, 45]);
        _addPart(ranges, last);
      }
      _addPart(ranges, first);
    }
    _at++;
    return _ranges(ranges, isNegated: isNegated);
  }

  static void _addPart(List<int> ranges, List<int> part) {
    ranges.addAll(part.length == 1 ? [part[0], part[0]] : part);
  }

  /// A single character, or ranges.
  List<int> _classPart() {
    if (_here != 92) return [_next()];
    _at++;
    if (_isDone) _fail(r'\ at end of pattern');
    final ranges = _classEscape();
    if (ranges != null) return ranges;
    if (_takes('b')) return const [8];
    if (_takes('-')) return const [45];
    return [_escaped()];
  }
}
