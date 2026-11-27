/// Programs that use ports within one isolate.
const portPrograms = {
  'messages among timers and microtasks': r'''
import 'dart:async';
import 'dart:isolate';

void main() {
  final port = RawReceivePort();
  var count = 0;
  port.handler = (message) {
    print('message $message');
    scheduleMicrotask(() => print('microtask after $message'));
    if (message == 2) Timer.run(() => print('timer from 2'));
    if (message == 2) port.sendPort.send(4);
    if (++count == 4) port.close();
  };
  Timer.run(() => print('timer 1'));
  port.sendPort.send(1);
  Timer.run(() => print('timer 2'));
  port.sendPort.send(2);
  scheduleMicrotask(() => print('microtask'));
  Future(() => print('future'));
  port.sendPort.send(3);
  Timer(Duration(milliseconds: 200), () => print('later'));
  print('end of main');
}
''',
  'what is copied': r'''
import 'dart:isolate';
import 'dart:typed_data';

class Point {
  final int x, y;
  Point(this.x, this.y);
  String toString() => 'Point($x, $y)';
}

class Key {}

enum Color { red, green }

/// A function that counts from [start], and one that tells how far.
(int Function(), int Function()) counter(int start) {
  var count = start;
  return (() => count, () => count++);
}

void main() async {
  final port = ReceivePort();
  final messages = port.asBroadcastStream();
  Future<Object?> echo(Object? message) {
    port.sendPort.send(message);
    return messages.first;
  }

  for (final value in [
    null, true, 42, -1 << 62, 3.25, double.nan, 'text', 'été ☃', '',
    [1, 'a', null], <String, int>{'a': 1, 'b': 2}, {1, 2, 3},
    (1, 'two', name: 3.0), Point(1, 2), Color.green, const [1, 2],
    Uint8List.fromList([1, 2, 255]), Float64List.fromList([0.5, -2]),
    Int32List(3)..[1] = -7, Duration(seconds: 3),
    DateTime.utc(2024, 2, 29), #symbol, BigInt.parse('123456789012345678901234567890'),
  ]) {
    final copy = await echo(value);
    print('$copy ${copy.runtimeType} ${copy == value}');
  }

  final list = [1, 2];
  port.sendPort.send(list);
  list.add(3);
  print(await messages.first);

  final cycle = <Object?>[1];
  cycle.add(cycle);
  final copy = await echo(cycle) as List;
  print(identical(copy, copy[1]));
  print(identical(copy, cycle));

  final key = Key();
  final shared = [key, key, {key: 'value'}, {key}];
  final back = await echo(shared) as List;
  print(identical(back[0], back[1]));
  print(identical(back[0], key));
  print((back[2] as Map)[back[0]]);
  print((back[3] as Set).contains(back[0]));

  final bytes = Uint8List.fromList(List.generate(16, (i) => i));
  final view = Uint16List.view(bytes.buffer, 4, 2);
  final views = await echo([bytes, view]) as List;
  print(views[1]);
  (views[0] as Uint8List)[4] = 100;
  print(views[1]);
  print(view);

  final (count, next) = counter(10);
  final function = await echo(next) as int Function();
  print(function());
  print(function());
  print(count());

  final types = await echo([int, List<String>, Point]) as List;
  print(types);
  print(types[0] == int && types[1] == List<String>);

  final weak = WeakReference(key);
  final weaks = await echo([weak, WeakReference(Key())]) as List;
  print(weaks[0].target == null);

  final many = List.generate(1000, (i) => [i, '$i']);
  final copied = await echo(many) as List;
  print(copied.length);
  print(copied[999]);
  port.close();
}
''',
  'what is not sent': r'''
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

class Holder {
  final Object value;
  Holder(this.value);
}

void main() {
  final port = RawReceivePort((message) => print('got $message'));
  final receive = ReceivePort(), raw = RawReceivePort();
  final future = Future.value(1);
  for (final value in [
    receive, raw, Finalizer<int>((_) {}),
    NativeFinalizer(Pointer.fromAddress(8)), DynamicLibrary.process(),
    future, Completer<int>(), Holder(future), [1, future], {'a': receive},
    Stream.value(1), Zone.current, Timer(Duration.zero, () {}),
  ]) {
    try {
      port.sendPort.send(value);
      print('sent');
    } on ArgumentError catch (error) {
      final message = error.message as String;
      print(message.startsWith('Illegal argument in isolate message: '));
      if (message.contains('(object is a')) print(message.trim());
      print(error.name);
    }
  }
  receive.close();
  raw.close();
  port.sendPort.send('after all');
  Timer.run(port.close);
}
''',
  'receive ports as streams': r'''
import 'dart:async';
import 'dart:isolate';

void main() async {
  final port = ReceivePort();
  for (var i = 0; i < 5; i++) {
    port.sendPort.send(i);
  }
  print(await port.take(3).toList());

  final second = ReceivePort();
  second.sendPort.send('a');
  second.sendPort.send('b');
  final subscription = second.listen((message) => print('listened $message'));
  await Future.delayed(Duration(milliseconds: 1));
  subscription.pause();
  second.sendPort.send('c');
  await Future.delayed(Duration(milliseconds: 1));
  print('paused');
  subscription.resume();
  await Future.delayed(Duration(milliseconds: 1));
  await subscription.cancel();
  second.sendPort.send('dropped');

  final third = ReceivePort();
  third.listen(print, onDone: () => print('done'));
  third.sendPort.send('last');
  await Future.delayed(Duration(milliseconds: 1));
  third.close();

  final raw = RawReceivePort();
  final sendPort = raw.sendPort;
  print(sendPort == raw.sendPort);
  print(sendPort.hashCode == raw.sendPort.hashCode);
  final other = ReceivePort();
  print(sendPort == other.sendPort);
  other.close();
  print(raw.keepIsolateAlive);
  raw.keepIsolateAlive = false;
  final capability = Capability();
  print(capability == capability);
  print(capability == Capability());
  final current = Isolate.current;
  print(current.debugName);
  print(identical(current, Isolate.current));
  print(current.controlPort == Isolate.current.controlPort);
  print(current.pauseCapability != null);
  final copies = ReceivePort();
  copies.sendPort.send([capability, sendPort, current.controlPort]);
  final back = await copies.first as List;
  print(back[0] == capability);
  print(back[1] == sendPort);
  print(back[2] == current.controlPort);
}
''',
};
