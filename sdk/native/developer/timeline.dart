import 'dart:_heap/objects.dart' show steadyTime;

// Nothing records what programs tell, as with the official compiler in product
// mode.

@patch
bool _isDartStreamEnabled() => false;

int _lastTaskId = 0;

@patch
int _getNextTaskId() => ++_lastTaskId;

@patch
int _getTraceClock() => steadyTime() ~/ 1000;

@patch
void _reportTaskEvent(
  int taskId,
  int flowId,
  int type,
  String name,
  String argumentsAsJson,
) {}

@patch
void log(
  String message, {
  DateTime? time,
  int? sequenceNumber,
  int level = 0,
  String name = '',
  Zone? zone,
  Object? error,
  StackTrace? stackTrace,
}) {}
