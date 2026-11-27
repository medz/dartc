import 'dart:developer';

void attempt(String name, Object? Function() work) {
  try {
    print('$name: ${work()}');
  } catch (e) {
    print('$name fails: $e');
  }
}

void main() {
  attempt('inspect', () => inspect('x')); // expect: inspect: x
  attempt('debugger', () => debugger(when: false)); // expect: debugger: false
  attempt(
    'snapshot',
    () => NativeRuntime.stopStreamingTimeline(),
  ); // expect: snapshot: null
  attempt(
    'chrome',
    () => NativeRuntime.streamTimelineTo(TimelineRecorder.chrome),
  ); // expect: chrome fails: Invalid argument (path): TimelineRecorder.chrome needs an output file to write timeline data to: null
  attempt(
    'interval',
    () => NativeRuntime.streamTimelineTo(
      TimelineRecorder.perfetto,
      path: 'x',
      samplingInterval: Duration.zero,
    ),
  ); // expect: interval fails: Invalid argument (samplingInterval): should be at least 50 us: Instance of 'Duration'
  final a = UserTag('a');
  attempt('same', () => identical(a, UserTag('a'))); // expect: same: true
  attempt('label', () => a.label); // expect: label: a
  attempt(
    'default',
    () => UserTag.defaultTag.label,
  ); // expect: default: Default
  attempt('current', () => getCurrentTag().label); // expect: current: Default
  attempt('before', () => a.makeCurrent().label); // expect: before: Default
  attempt('now', () => getCurrentTag().label); // expect: now: a
  attempt(
    'back',
    () => UserTag.defaultTag.makeCurrent().label,
  ); // expect: back: a
  attempt('max', () => UserTag.maxUserTags); // expect: max: 64
  for (var i = 2; i < 255; i++) {
    UserTag('tag-$i');
  }
  attempt(
    'last tag',
    () => UserTag('tag-255').label,
  ); // expect: last tag: tag-255
  attempt('too many tags', () => UserTag('overflow').label); // expect: too many tags fails: Unsupported operation: UserTag instance limit (256) reached.
  attempt(
    'existing tag at the limit',
    () => identical(a, UserTag('a')),
  ); // expect: existing tag at the limit: true
  attempt('post', () => postEvent('k', {'a': 1}, stream: 'VM')); // expect: post fails: Invalid argument (stream): Cannot be a protected stream.: "VM"
  attempt('post', () => postEvent('k', {'a': 1}, stream: '_x')); // expect: post fails: Invalid argument (stream): Cannot start with an underscore.: "_x"
  attempt('register', () => registerExtension('a', (_, _) async => throw 0)); // expect: register fails: Invalid argument (method): Must begin with ext.: "a"
  attempt(
    'response',
    () => ServiceExtensionResponse.error(-32000, 'x').errorDetail,
  ); // expect: response: x
  attempt(
    'response',
    () => ServiceExtensionResponse.error(5, 'x'),
  ); // expect: response fails: Invalid argument (errorCode): Out of range: 5
}
