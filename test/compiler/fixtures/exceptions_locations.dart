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
  final firstTrace = chooseTrace(true);
  final secondTrace = chooseTrace(false);
  allocate(40000);
  final first = firstTrace.toString();
  final second = secondTrace.toString();
  if (!first.contains('exceptions_locations.dart:3:') ||
      !first.contains('exceptions_locations.dart:7:12)') ||
      !second.contains('exceptions_locations.dart:9:10)')) {
    return false;
  }
  try {
    throwInPart();
  } catch (_, trace) {
    return trace.toString().contains('exceptions_locations.dart:13:3)') &&
        inlinedSourceLocations();
  }
}

int inlineTraceNull(int? value) => value!;

bool inlinedSourceLocations() {
  try {
    inlineTraceNull(null);
  } catch (_, trace) {
    final text = trace.toString();
    final leaf = text.indexOf('inlineTraceNull (');
    final caller = text.indexOf('inlinedSourceLocations (');
    return leaf >= 0 && caller > leaf;
  }
  return false;
}
