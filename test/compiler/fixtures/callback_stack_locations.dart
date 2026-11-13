import 'dart:async';

part 'callback_stack_locations_part.dart';

Future<StackTrace> leaf() async {
  await Future<void>.value();
  return StackTrace.current;
}

StackTrace topCallback(StackTrace trace) => trace;
T genericCallback<T>(T value) => value;

class Receiver() {
  StackTrace instanceCallback(StackTrace trace) => trace;
}

class TraceBox(final StackTrace trace) {
  factory copy(StackTrace trace) => TraceBox(trace);
  factory redirect(StackTrace trace) = TraceBox;
}

typedef TraceAlias = TraceBox;

Future<StackTrace> topParent() async => await leaf().then(topCallback);
Future<StackTrace> genericParent() async {
  final generic = genericCallback;
  return await leaf().then(generic<StackTrace>);
}

Future<StackTrace> instanceParent() async =>
    await leaf().then(Receiver().instanceCallback);
Future<StackTrace> constructorParent() async =>
    (await leaf().then(TraceBox.new)).trace;
Future<StackTrace> factoryParent() async =>
    (await leaf().then(TraceBox.copy)).trace;
Future<StackTrace> partParent() async => await leaf().then(partCallback);
Future<StackTrace> sdkParent() async => (await Future.wait([leaf()])).single;

Future<StackTrace> redirectParent() async =>
    (await leaf().then(TraceBox.redirect)).trace;
Future<StackTrace> aliasParent() async =>
    (await leaf().then(TraceAlias.new)).trace;

Future<StackTrace> extensionParent() async =>
    await leaf().then(Object().extensionCallback);

void emit(String label, StackTrace trace) {
  print('BEGIN $label');
  print(trace);
  print('END $label');
}

Future<void> main() async {
  emit('top', await topParent());
  emit('generic', await genericParent());
  emit('instance', await instanceParent());
  emit('constructor', await constructorParent());
  emit('factory', await factoryParent());
  emit('part', await partParent());
  emit('sdk', await sdkParent());
  emit('redirect', await redirectParent());
  emit('alias', await aliasParent());
  emit('extension', await extensionParent());
}
