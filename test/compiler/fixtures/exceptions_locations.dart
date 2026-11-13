part of 'exceptions.dart';

StackTrace traceInPart() => StackTrace.current;

StackTrace chooseTrace(bool first) {
  if (first) {
    return traceInPart();
  }
  return traceInPart();
}

Never throwInPart() {
  throw StateError('located');
}

bool sourceLocations() {
  final first = chooseTrace(true).toString();
  final second = chooseTrace(false).toString();
  if (!first.contains('exceptions_locations.dart:3:') ||
      !first.contains('exceptions_locations.dart:7:12)') ||
      !second.contains('exceptions_locations.dart:9:10)')) {
    return false;
  }
  try {
    throwInPart();
  } catch (_, trace) {
    return trace.toString().contains('exceptions_locations.dart:13:3)');
  }
}
