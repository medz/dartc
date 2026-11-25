// Sets of characters, as pairs of the first and last of ranges.

/// [ranges] in order, without those that touch each other.
List<int> _orderedRanges(List<int> ranges) {
  var runs = <List<int>>[];
  var start = 0;
  for (var i = 2; i <= ranges.length; i += 2) {
    if (i < ranges.length && ranges[i] >= ranges[i - 2]) continue;
    runs.add(ranges.sublist(start, i));
    start = i;
  }
  if (runs.isEmpty) return const [];
  while (runs.length > 1) {
    final merged = <List<int>>[];
    for (var i = 0; i < runs.length; i += 2) {
      merged.add(
        i + 1 < runs.length ? _mergeRanges(runs[i], runs[i + 1]) : runs[i],
      );
    }
    runs = merged;
  }
  final ordered = runs.single, result = <int>[];
  for (var i = 0; i < ordered.length; i += 2) {
    if (result.isEmpty || ordered[i] > result.last + 1) {
      result.add(ordered[i]);
      result.add(ordered[i + 1]);
    } else if (ordered[i + 1] > result.last) {
      result[result.length - 1] = ordered[i + 1];
    }
  }
  return result;
}

List<int> _mergeRanges(List<int> a, List<int> b) {
  final result = List.filled(a.length + b.length, 0);
  var i = 0, j = 0;
  for (var at = 0; at < result.length; at += 2) {
    if (j == b.length || i < a.length && a[i] <= b[j]) {
      result[at] = a[i];
      result[at + 1] = a[i + 1];
      i += 2;
    } else {
      result[at] = b[j];
      result[at + 1] = b[j + 1];
      j += 2;
    }
  }
  return result;
}

/// What is not in [ranges], which are in order.
List<int> _otherRanges(List<int> ranges) {
  final result = <int>[];
  var from = 0;
  for (var i = 0; i < ranges.length; i += 2) {
    if (ranges[i] > from) result.addAll([from, ranges[i] - 1]);
    from = ranges[i + 1] + 1;
  }
  if (from <= 0x10ffff) result.addAll([from, 0x10ffff]);
  return result;
}

/// Whether [character] is in [ranges], which are in order.
bool _isInRanges(List<int> ranges, int character) =>
    _overlaps(ranges, character, character);

/// Whether any of [first] to [last] is in [ranges], which are in order.
bool _overlaps(List<int> ranges, int first, int last) {
  var low = 0, high = ranges.length >> 1;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (ranges[middle * 2 + 1] < first) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low * 2 < ranges.length && ranges[low * 2] <= last;
}

/// The character that stands for all that differ from [character] only in
/// their case.
int _foldCharacter(int character, bool isUnicode) {
  if (character < 128) {
    return character >= 97 && character <= 122 ? character - 32 : character;
  }
  return _changeCase(character, isUnicode ? _unicodeFolds : _folds);
}

/// [ranges], which are in order, and what differs from them only in its case.
List<int> _foldedRanges(List<int> ranges, bool isUnicode) {
  if (ranges.isEmpty) return ranges;
  final result = [...ranges];
  if (!isUnicode && ranges.last < 128) {
    void add(int first, int last, int distance) {
      for (var i = 0; i < ranges.length; i += 2) {
        final from = ranges[i] > first ? ranges[i] : first;
        final to = ranges[i + 1] < last ? ranges[i + 1] : last;
        if (from <= to) result.addAll([from + distance, to + distance]);
      }
    }

    add(65, 90, 32);
    add(97, 122, -32);
    return _orderedRanges(result);
  }
  final found = <int>[];
  _eachFold(
    isUnicode,
    (first, last, distance) {
      return _overlaps(ranges, first, last) ||
          _overlaps(ranges, first + distance, last + distance);
    },
    (character, least) {
      if (_isInRanges(ranges, character) || _isInRanges(ranges, least)) {
        found
          ..add(least)
          ..add(least);
      }
    },
  );
  final all = _orderedRanges(found);
  _eachFold(
    isUnicode,
    (first, last, distance) {
      return _overlaps(all, first + distance, last + distance);
    },
    (character, least) {
      if (!_isInRanges(all, least)) return;
      result
        ..add(character)
        ..add(character)
        ..add(least)
        ..add(least);
    },
  );
  return _orderedRanges(result);
}

/// Calls [use] for characters and those that stand for them, where [isUsed]
/// holds for some between a first and last one.
void _eachFold(
  bool isUnicode,
  bool Function(int first, int last, int distance) isUsed,
  void Function(int character, int least) use,
) {
  final folds = isUnicode ? _unicodeFolds : _folds;
  for (var i = 0; i < folds.length; i += 4) {
    final first = folds[i], step = folds[i + 2], distance = folds[i + 3];
    final last = first + (folds[i + 1] - 1) * step;
    if (!isUsed(first, last, distance)) continue;
    for (var character = first; character <= last; character += step) {
      use(character, character + distance);
      if (step == 0) break;
    }
  }
}

/// The characters that the property [text] holds for, if there is such a one.
List<int>? _propertyRanges(String text) {
  final equals = text.indexOf('=');
  if (equals < 0) {
    return _categoryRanges(text) ??
        _namedRanges(text, _propertyNames, _propertySets);
  }
  final value = text.substring(equals + 1);
  switch (text.substring(0, equals)) {
    case 'General_Category' || 'gc':
      return _categoryRanges(value);
    case 'Script' || 'sc':
      return _namedRanges(value, _scriptNames, _scriptSets);
    case 'Script_Extensions' || 'scx':
      final index = _indexOfName(value, _scriptNames);
      if (index < 0) return null;
      final more = _scriptExtensionSets[index];
      return _rangesIn(more.isEmpty ? _scriptSets[index] : more);
  }
  return null;
}

List<int>? _categoryRanges(String name) {
  for (final group in _categoryGroups) {
    final equals = group.indexOf('=');
    if (!_isOneOf(name, group.substring(0, equals))) continue;
    return _orderedRanges([
      for (final part in group.substring(equals + 1).split('+'))
        ...?_namedRanges(part, _categoryNames, _categorySets),
    ]);
  }
  return _namedRanges(name, _categoryNames, _categorySets);
}

List<int>? _namedRanges(String name, List<String> names, List<String> sets) {
  final index = _indexOfName(name, names);
  return index < 0 ? null : _rangesIn(sets[index]);
}

int _indexOfName(String name, List<String> names) {
  for (var i = 0; i < names.length; i++) {
    if (_isOneOf(name, names[i])) return i;
  }
  return -1;
}

bool _isOneOf(String name, String names) => names.split(',').contains(name);

/// The ranges that [text] has. What made it tells how.
List<int> _rangesIn(String text) {
  final result = <int>[];
  var at = 0, value = 0, scale = 1;
  for (var i = 0; i < text.length; i++) {
    final digit = text.codeUnitAt(i) - 40;
    if (digit >= 43) {
      value += (digit - 43) * scale;
      scale *= 43;
    } else {
      at += value + digit * scale;
      value = 0;
      scale = 1;
      // They tell where ranges end, rather than what is last.
      result.add(result.length.isEven ? at : at - 1);
    }
  }
  return result;
}
