// Regular expressions, as ECMAScript and the official runtime define them.

@patch
class _RegExp {
  @patch
  final String pattern;
  @patch
  final bool isMultiLine;
  @patch
  final bool isCaseSensitive;
  @patch
  final bool isUnicode;
  @patch
  final bool isDotAll;
  @patch
  final int _groupCount;
  @patch
  final List? _groupNameList;
  final _Matcher _matcher;

  _RegExp._of(
    this.pattern,
    this.isMultiLine,
    this.isCaseSensitive,
    this.isUnicode,
    this.isDotAll,
    this._groupCount,
    this._groupNameList,
    this._matcher,
  );

  @patch
  factory _RegExp(
    String pattern, {
    bool multiLine = false,
    bool caseSensitive = true,
    bool unicode = false,
    bool dotAll = false,
  }) {
    final parser = _RegExpParser(
      pattern,
      multiLine,
      !caseSensitive,
      unicode,
      dotAll,
    );
    final matcher = parser.parse();
    final names = [];
    parser.names.forEach((name, index) {
      names.add(name);
      names.add(index);
    });
    return _RegExp._of(
      pattern,
      multiLine,
      caseSensitive,
      unicode,
      dotAll,
      parser.groupCount,
      names.isEmpty ? null : names,
      matcher,
    );
  }

  String toString() {
    final flags = [
      if (!isCaseSensitive) 'i',
      if (isMultiLine) 'm',
      if (isDotAll) 's',
      if (isUnicode) 'u',
    ].join();
    // The official runtime has one name that is out of order.
    final shown = flags == 'isu' ? 'ius' : flags;
    return 'RegExp: pattern=$pattern flags=$shown';
  }

  @patch
  Int32List? _ExecuteMatch(String str, int start_index) {
    for (var at = start_index; at <= str.length; at++) {
      if (at > start_index && _isInside(str, at)) continue;
      final found = _ExecuteMatchSticky(str, at);
      if (found != null) return found;
    }
    return null;
  }

  /// Whether a character that takes two units continues at [at].
  bool _isInside(String str, int at) =>
      isUnicode &&
      at > 0 &&
      at < str.length &&
      str.codeUnitAt(at) & 0xfc00 == 0xdc00 &&
      str.codeUnitAt(at - 1) & 0xfc00 == 0xd800;

  @patch
  Int32List? _ExecuteMatchSticky(String str, int start_index) {
    final start = _isInside(str, start_index) ? start_index - 1 : start_index;
    final groups = Int32List(_groupCount * 2 + 2);
    groups.fillRange(0, groups.length, -1);
    final run = _RegExpRun(str, groups);
    final isFound = _matcher.match(run, start, (end) {
      groups[0] = start;
      groups[1] = end;
      return true;
    });
    return isFound ? groups : null;
  }
}

/// One attempt to match [input], with where the groups start and end.
final class _RegExpRun {
  final String input;
  final Int32List groups;
  _RegExpRun(this.input, this.groups);
}

/// A part of a regular expression.
///
/// Matches from [at] on, or before it where the part looks behind, and then
/// what follows. Tries the next way to match if that fails.
abstract class _Matcher {
  const _Matcher();
  bool match(_RegExpRun run, int at, bool Function(int at) then);
}

/// A part that matches one character.
abstract class _SingleMatcher extends _Matcher {
  final bool isUnicode, isBackward;
  const _SingleMatcher(this.isUnicode, this.isBackward);

  bool accepts(int character);

  /// Where it goes on after matching at [at], or -1.
  int step(_RegExpRun run, int at) {
    final input = run.input;
    if (isBackward) {
      if (at == 0) return -1;
      var unit = input.codeUnitAt(at - 1), next = at - 1;
      if (isUnicode && unit & 0xfc00 == 0xdc00 && next > 0) {
        final lead = input.codeUnitAt(next - 1);
        if (lead & 0xfc00 == 0xd800) {
          unit = ((lead - 0xd7c0) << 10) + (unit & 0x3ff);
          next--;
        }
      }
      return accepts(unit) ? next : -1;
    }
    if (at >= input.length) return -1;
    var unit = input.codeUnitAt(at), next = at + 1;
    if (isUnicode && unit & 0xfc00 == 0xd800 && next < input.length) {
      final trail = input.codeUnitAt(next);
      if (trail & 0xfc00 == 0xdc00) {
        unit = ((unit - 0xd7c0) << 10) + (trail & 0x3ff);
        next++;
      }
    }
    return accepts(unit) ? next : -1;
  }

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    final next = step(run, at);
    return next >= 0 && then(next);
  }
}

final class _CharacterMatcher extends _SingleMatcher {
  final int character;
  const _CharacterMatcher(this.character, super.isUnicode, super.isBackward);
  bool accepts(int other) => other == character;
}

/// Matches what has the same upper case.
final class _FoldedMatcher extends _SingleMatcher {
  final int character;
  const _FoldedMatcher(this.character, super.isUnicode, super.isBackward);
  bool accepts(int other) => _foldCharacter(other, isUnicode) == character;
}

/// Anything, or anything that ends no line.
final class _AnyMatcher extends _SingleMatcher {
  final bool isDotAll;
  const _AnyMatcher(this.isDotAll, super.isUnicode, super.isBackward);
  bool accepts(int other) => isDotAll || !_endsLine(other);
}

/// Characters that are in [ranges], which are in order, or not.
final class _ClassMatcher extends _SingleMatcher {
  final List<int> ranges;
  final bool isNegated;
  const _ClassMatcher(
    this.ranges,
    this.isNegated,
    super.isUnicode,
    super.isBackward,
  );

  bool accepts(int other) => _isInRanges(ranges, other) != isNegated;
}

bool _endsLine(int character) =>
    character == 10 ||
    character == 13 ||
    character == 0x2028 ||
    character == 0x2029;

final class _SequenceMatcher extends _Matcher {
  final List<_Matcher> parts;
  const _SequenceMatcher(this.parts);

  bool match(_RegExpRun run, int at, bool Function(int at) then) =>
      _from(0, run, at, then);

  bool _from(int index, _RegExpRun run, int at, bool Function(int at) then) {
    // Single characters need no way back.
    var position = at;
    for (; index < parts.length; index++) {
      final part = parts[index];
      if (part is! _SingleMatcher) {
        final next = index + 1;
        if (next == parts.length) return part.match(run, position, then);
        return part.match(run, position, (end) => _from(next, run, end, then));
      }
      position = part.step(run, position);
      if (position < 0) return false;
    }
    return then(position);
  }
}

final class _EitherMatcher extends _Matcher {
  final List<_Matcher> options;
  const _EitherMatcher(this.options);

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    for (var i = 0; i < options.length; i++) {
      if (options[i].match(run, at, then)) return true;
    }
    return false;
  }
}

final class _RepeatMatcher extends _Matcher {
  final _Matcher part;

  /// At least and at most how often, the latter being -1 without a limit.
  final int least, most;
  final bool isGreedy;

  /// The groups inside.
  final int firstGroup, endGroup;
  const _RepeatMatcher(
    this.part,
    this.least,
    this.most,
    this.isGreedy,
    this.firstGroup,
    this.endGroup,
  );

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    final part = this.part;
    return part is _SingleMatcher
        ? _matchSingle(part, run, at, then)
        : _more(run, at, 0, then);
  }

  bool _matchSingle(
    _SingleMatcher part,
    _RegExpRun run,
    int at,
    bool Function(int at) then,
  ) {
    var count = 0, position = at;
    while (count < least) {
      position = part.step(run, position);
      if (position < 0) return false;
      count++;
    }
    if (!isGreedy) {
      while (!then(position)) {
        if (count == most) return false;
        position = part.step(run, position);
        if (position < 0) return false;
        count++;
      }
      return true;
    }
    final first = position;
    while (count != most) {
      final next = part.step(run, position);
      if (next < 0) break;
      position = next;
      count++;
    }
    while (true) {
      if (then(position)) return true;
      if (position == first) return false;
      position = _back(part, run, position);
    }
  }

  /// Where a part that ends at [at] started.
  static int _back(_SingleMatcher part, _RegExpRun run, int at) {
    final input = run.input;
    if (part.isBackward) {
      final isPair =
          part.isUnicode &&
          at + 1 < input.length &&
          input.codeUnitAt(at) & 0xfc00 == 0xd800 &&
          input.codeUnitAt(at + 1) & 0xfc00 == 0xdc00;
      return isPair ? at + 2 : at + 1;
    }
    final isPair =
        part.isUnicode &&
        at > 1 &&
        input.codeUnitAt(at - 1) & 0xfc00 == 0xdc00 &&
        input.codeUnitAt(at - 2) & 0xfc00 == 0xd800;
    return isPair ? at - 2 : at - 1;
  }

  bool _more(_RegExpRun run, int at, int count, bool Function(int at) then) {
    bool again() {
      if (count == most) return false;
      final groups = run.groups;
      final kept = groups.sublist(firstGroup * 2, endGroup * 2);
      groups.fillRange(firstGroup * 2, endGroup * 2, -1);
      final isFound = part.match(run, at, (next) {
        // Nothing more is gained by matching nothing.
        if (next == at && count >= least) return false;
        return _more(run, next, count + 1, then);
      });
      if (!isFound) {
        groups.setRange(firstGroup * 2, endGroup * 2, kept);
      }
      return isFound;
    }

    if (count < least) return again();
    return isGreedy ? again() || then(at) : then(at) || again();
  }
}

final class _GroupMatcher extends _Matcher {
  final _Matcher part;
  final int index;
  final bool isBackward;
  const _GroupMatcher(this.part, this.index, this.isBackward);

  bool match(_RegExpRun run, int at, bool Function(int at) then) =>
      part.match(run, at, (end) {
        final groups = run.groups;
        final first = groups[index * 2], last = groups[index * 2 + 1];
        groups[index * 2] = isBackward ? end : at;
        groups[index * 2 + 1] = isBackward ? at : end;
        if (then(end)) return true;
        groups[index * 2] = first;
        groups[index * 2 + 1] = last;
        return false;
      });
}

/// What a group matched before.
final class _BackMatcher extends _Matcher {
  final List<int> indexes;
  final bool isFolded, isUnicode, isBackward;
  const _BackMatcher(
    this.indexes,
    this.isFolded,
    this.isUnicode,
    this.isBackward,
  );

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    for (var i = 0; i < indexes.length; i++) {
      final first = run.groups[indexes[i] * 2];
      final last = run.groups[indexes[i] * 2 + 1];
      if (first < 0) continue;
      final length = last - first;
      final from = isBackward ? at - length : at;
      if (from < 0 || from + length > run.input.length) return false;
      for (var j = 0; j < length; j++) {
        if (!_isSame(run.input, first + j, from + j)) return false;
      }
      return then(isBackward ? from : from + length);
    }
    return then(at);
  }

  bool _isSame(String input, int first, int second) {
    final a = input.codeUnitAt(first), b = input.codeUnitAt(second);
    if (a == b) return true;
    if (!isFolded) return false;
    if (_foldCharacter(a, isUnicode) == _foldCharacter(b, isUnicode)) {
      return true;
    }
    if (!isUnicode || first == 0 || second == 0) return false;
    // The second halves of two characters.
    if (a & 0xfc00 != 0xdc00 || b & 0xfc00 != 0xdc00) return false;
    final lead = input.codeUnitAt(first - 1);
    if (lead & 0xfc00 != 0xd800) return false;
    final high = (lead - 0xd7c0) << 10;
    return _foldCharacter(high + (a & 0x3ff), true) ==
        _foldCharacter(high + (b & 0x3ff), true);
  }
}

final class _LookMatcher extends _Matcher {
  final _Matcher part;
  final bool isNegative;
  const _LookMatcher(this.part, this.isNegative);

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    final kept = run.groups.sublist(0);
    final isFound = part.match(run, at, (_) => true);
    if (isFound != isNegative && then(at)) return true;
    run.groups.setRange(0, kept.length, kept);
    return false;
  }
}

/// The start or end of the input, or of lines.
final class _EdgeMatcher extends _Matcher {
  final bool isEnd, isMultiLine;
  const _EdgeMatcher(this.isEnd, this.isMultiLine);

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    final input = run.input, edge = isEnd ? input.length : 0;
    if (at != edge) {
      if (!isMultiLine) return false;
      if (!_endsLine(input.codeUnitAt(isEnd ? at : at - 1))) return false;
    }
    return then(at);
  }
}

final class _WordMatcher extends _Matcher {
  final bool isNegated;

  /// All that words have.
  final List<int> words;
  const _WordMatcher(this.isNegated, this.words);

  bool match(_RegExpRun run, int at, bool Function(int at) then) {
    final input = run.input;
    bool isWord(int at) => _isInRanges(words, input.codeUnitAt(at));
    final before = at > 0 && isWord(at - 1);
    final after = at < input.length && isWord(at);
    return (before != after) != isNegated && then(at);
  }
}
