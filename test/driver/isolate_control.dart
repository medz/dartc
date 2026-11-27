/// Programs that control isolates.
const controlPrograms = {
  'errors and ends': r'''
import 'dart:async';
import 'dart:isolate';

void thrower(SendPort port) {
  Timer.run(() => throw StateError('first'));
  Timer(Duration(milliseconds: 20), () => throw StateError('second'));
  Timer(Duration(milliseconds: 40), () => port.send('survived'));
}

void main() async {
  final port = ReceivePort();
  final messages = port.asBroadcastStream();
  await Isolate.spawn(
    thrower,
    port.sendPort,
    onError: port.sendPort,
    onExit: port.sendPort,
  );
  final error = await messages.first as List;
  print([error[0], error[1].runtimeType, error.length]);
  print('exit ${await messages.first}');

  await Isolate.spawn(
    thrower,
    port.sendPort,
    onError: port.sendPort,
    onExit: port.sendPort,
    errorsAreFatal: false,
  );
  for (var i = 0; i < 4; i++) {
    final message = await messages.first;
    print(message is List ? message[0] : message);
  }

  final listened = await Isolate.spawn(
    thrower,
    port.sendPort,
    paused: true,
    errorsAreFatal: false,
  );
  listened.addErrorListener(port.sendPort);
  listened.addOnExitListener(port.sendPort, response: 'gone');
  listened.setErrorsFatal(true);
  listened.resume(listened.pauseCapability!);
  print((await messages.first as List)[0]);
  print(await messages.first);
  port.close();
}
''',
  'pausing, pinging and killing': r'''
import 'dart:async';
import 'dart:isolate';

void echo(SendPort port) {
  final requests = ReceivePort();
  port.send(requests.sendPort);
  requests.listen((message) => port.send('echo $message'));
}

void main() async {
  final port = ReceivePort();
  final messages = port.asBroadcastStream();
  final isolate = await Isolate.spawn(echo, port.sendPort, paused: true);
  isolate.addOnExitListener(port.sendPort, response: 'bye');
  isolate.ping(port.sendPort, response: 'pong while paused');
  print(await messages.first);
  isolate.resume(isolate.pauseCapability!);
  final requests = await messages.first as SendPort;
  requests.send(1);
  print(await messages.first);

  final resume = isolate.pause();
  requests.send(2);
  isolate.ping(port.sendPort, response: 'later', priority: Isolate.beforeNextEvent);
  isolate.ping(port.sendPort, response: 'now');
  print(await messages.first);
  await Future.delayed(Duration(milliseconds: 20));
  print('resuming');
  isolate.resume(Capability());
  isolate.resume(resume);
  print(await messages.first);
  print(await messages.first);

  isolate.kill(priority: Isolate.immediate);
  print(await messages.first);
  print(isolate.debugName);
  requests.send('to nobody');
  isolate.kill();
  port.close();
}
''',
  'exits and runs': r'''
import 'dart:async';
import 'dart:isolate';

void leave(SendPort port) {
  try {
    Isolate.exit(port, [1, 'last']);
  } catch (error) {
    port.send('caught');
  } finally {
    port.send('finally');
  }
}

int fibonacci(int n) => n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2);

void main() async {
  final port = ReceivePort();
  final messages = port.asBroadcastStream();
  await Isolate.spawn(leave, port.sendPort, onExit: port.sendPort);
  print(await messages.first);
  print(await messages.first);

  print(await Isolate.run(() => fibonacci(20)));
  print(await Isolate.run(() async {
    await Future.delayed(Duration(milliseconds: 5));
    return [Isolate.current.debugName, 'done'];
  }, debugName: 'runner'));
  try {
    await Isolate.run(() => throw ArgumentError('bad'));
  } catch (error, trace) {
    print('caught $error ${trace is StackTrace}');
  }
  try {
    await Isolate.run<int>(() => Isolate.exit());
  } catch (error) {
    print('caught $error');
  }
  try {
    await Isolate.run(() {
      Timer.run(() => throw StateError('later'));
      return Completer<int>().future;
    });
  } on RemoteError catch (error) {
    print('remote ${error.toString()}');
  }
  final results = await Future.wait([
    for (var i = 0; i < 5; i++) Isolate.run(() => i * i),
  ]);
  print(results);
  port.close();
  print('main ends');
  Isolate.current.kill();
  print('after kill');
}
''',
};

/// A program whose isolate ends with an error that nothing listens for.
const uncaughtProgram = r'''
import 'dart:isolate';

void fail(SendPort port) {
  port.send('failing');
  throw StateError('boom');
}

void main() async {
  final port = ReceivePort();
  await Isolate.spawn(fail, port.sendPort, onExit: port.sendPort);
  await for (final message in port) {
    print(message);
    if (message == null) break;
  }
  print('main goes on');
}
''';
