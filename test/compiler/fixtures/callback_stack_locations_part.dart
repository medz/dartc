part of 'callback_stack_locations.dart';

@pragma('vm:never-inline')
StackTrace partCallback(StackTrace trace) => trace;

extension TraceCallbacks on Object {
  StackTrace extensionCallback(StackTrace trace) => trace;
}
