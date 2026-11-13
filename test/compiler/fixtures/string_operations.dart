// Exercise String operators, including multiplication and explicit concatenation.
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:ffi';

import 'package:dartc/interop.dart';

String transform(String value, String pattern, int mode, int first, int last) {
  final end = last < 0 ? null : last;
  switch (mode) {
    case 0:
      return value.substring(first, end);
    case 1:
      return value.trim();
    case 2:
      return value.trimLeft();
    case 3:
      return value.trimRight();
    case 4:
      return value * first;
    case 5:
      return value.padLeft(first, pattern);
    case 6:
      return value.padRight(first, pattern);
    case 7:
      return value.replaceRange(first, end, pattern);
    case 8:
      return value.replaceFirst(pattern, '#', first);
    case 9:
      return value.replaceAll(pattern, '#');
    case 10:
      return value.replaceAllMapped(pattern, (match) => '[' + match[0]! + ']');
    case 11:
      return value.replaceFirstMapped(
        pattern,
        (match) => '[' + match[0]! + ']',
        first,
      );
    case 12:
      var result = '';
      for (final piece in value.split(pattern)) {
        result = result + piece + '|';
      }
      return result;
    case 13:
      return String.fromCharCodes(value.runes);
    case 15:
      return value.splitMapJoin(
        pattern,
        onMatch: (match) => '[' + match[0]! + ']',
        onNonMatch: (part) => '<' + part + '>',
      );
    case 16:
      return value.splitMapJoin(pattern);
    case 17:
      return value.splitMapJoin(
        TracingPattern(pattern),
        onMatch: (match) => '[' + match[0]! + ']',
        onNonMatch: (part) => '<' + part + '>',
      );
    case 18:
      _trace = 0;
      final result = value.replaceAllMapped(TracingPattern(pattern), (match) {
        _trace = _trace * 10 + 3;
        return '[${match.start}:${match.end}]';
      });
      return '$_trace/$result';
    default:
      return value.toString();
  }
}

String? _saved;

@Export<
  Int64 Function(
    Pointer<Uint16>,
    Int64,
    Pointer<Uint16>,
    Int64,
    Int32,
    Int64,
    Int64,
    Pointer<Uint16>,
    Int64,
  )
>()
int transformBuffer(
  Pointer<Uint16> input,
  int length,
  Pointer<Uint16> pattern,
  int patternLength,
  int mode,
  int first,
  int last,
  Pointer<Uint16> output,
  int capacity,
) {
  try {
    _saved = transform(
      String.fromCharCodes(input.asTypedList(length)),
      String.fromCharCodes(pattern.asTypedList(patternLength)),
      mode,
      first,
      last,
    );
    for (var i = 0; i < 4000; i++) {
      String.fromCharCode(i);
    }
    return copySaved(output, capacity);
  } on RangeError {
    return -1;
  }
}

@Export<Int64 Function(Pointer<Uint16>, Int64)>()
int copySaved(Pointer<Uint16> output, int capacity) {
  final value = _saved!;
  if (value.length > capacity) return -2;
  for (var i = 0; i < value.length; i++) {
    output[i] = value.codeUnitAt(i);
  }
  return value.length;
}

int _trace = 0;

final class TracingPattern(final String pattern) implements Pattern {
  @override
  Iterable<Match> allMatches(String input, [int start = 0]) {
    _trace = _trace * 10 + 1;
    return pattern.allMatches(input, start);
  }

  @override
  Match? matchAsPrefix(String input, [int start = 0]) {
    _trace = _trace * 10 + 2;
    return pattern.matchAsPrefix(input, start);
  }
}

int inspect(String input, String pattern, int mode, int start) {
  _trace = 0;
  final Pattern selected = mode >= 10 ? TracingPattern(pattern) : pattern;
  try {
    final result = switch (mode % 10) {
      0 => input.indexOf(selected, start),
      1 => input.lastIndexOf(selected, start == -1 ? null : start),
      2 => input.startsWith(selected, start) ? 1 : 0,
      3 => input.contains(selected, start) ? 1 : 0,
      4 => input.endsWith(pattern) ? 1 : 0,
      5 => input.compareTo(pattern).sign,
      6 =>
        selected
            .allMatches(input, start)
            .fold<int>(
              0,
              (sum, match) =>
                  sum + match.start * 17 + match.end + match.groupCount,
            ),
      7 => selected.matchAsPrefix(input, start)?.end ?? -1,
      _ => input.isEmpty ? 1 : 0,
    };
    return result * 100000 + _trace;
  } on RangeError {
    return -9000000 + _trace;
  }
}

@Export<
  Int64 Function(Pointer<Uint16>, Int64, Pointer<Uint16>, Int64, Int32, Int64)
>()
int inspectBuffer(
  Pointer<Uint16> input,
  int length,
  Pointer<Uint16> pattern,
  int patternLength,
  int mode,
  int start,
) => inspect(
  String.fromCharCodes(input.asTypedList(length)),
  String.fromCharCodes(pattern.asTypedList(patternLength)),
  mode,
  start,
);
