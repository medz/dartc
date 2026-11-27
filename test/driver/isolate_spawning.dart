/// Programs that start isolates.
const spawningPrograms = {
  'talking to isolates': r'''
import 'dart:isolate';

class Request {
  final int number;
  final SendPort reply;
  Request(this.number, this.reply);
}

/// Answers requests until it is told to stop.
void server(SendPort parent) {
  final requests = ReceivePort();
  parent.send(requests.sendPort);
  requests.listen((message) {
    if (message is Request) {
      message.reply.send([message.number, message.number * message.number]);
    } else {
      requests.close();
    }
  });
}

class Box {
  static void report(SendPort port) => port.send(Isolate.current.debugName);
}

void main() async {
  final port = ReceivePort();
  final messages = port.asBroadcastStream();
  final isolate = await Isolate.spawn(server, port.sendPort);
  print(isolate.controlPort == Isolate.current.controlPort);
  final requests = await messages.first as SendPort;
  for (var i = 1; i <= 3; i++) {
    requests.send(Request(i, port.sendPort));
    print(await messages.first);
  }
  requests.send('stop');

  for (final entry in <void Function(SendPort)>[
    Box.report,
    (port) => port.send(Isolate.current.debugName),
  ]) {
    await Isolate.spawn(entry, port.sendPort);
    print(await messages.first);
  }
  await Isolate.spawn(Box.report, port.sendPort, debugName: 'worker');
  print(await messages.first);
  print(Isolate.current.debugName);
  port.close();
}
''',
  'many isolates at once': r'''
import 'dart:isolate';

/// Adds up numbers, making garbage as it goes.
void work(List<Object> message) {
  final [SendPort port, int index, int count] = message as List;
  var sum = 0;
  final lists = <List<int>>[];
  for (var i = 0; i < count; i++) {
    lists.add(List.filled(8, i));
    if (lists.length > 50) lists.clear();
    sum += i * index;
  }
  port.send([index, sum, '${'x' * index}']);
}

const lots = 20000;

void main() async {
  final port = ReceivePort();
  const count = 8;
  for (var i = 0; i < count; i++) {
    await Isolate.spawn(work, [port.sendPort, i, lots]);
  }
  final results = <int, List>{};
  await for (final message in port) {
    final list = message as List;
    results[list[0] as int] = list;
    if (results.length == count) break;
  }
  for (var i = 0; i < count; i++) {
    print(results[i]);
  }
}
''',
  'isolates that start isolates': r'''
import 'dart:async';
import 'dart:isolate';

void level(List<Object> message) {
  final [SendPort port, int depth] = message as List;
  if (depth == 0) {
    port.send('bottom ${Isolate.current.debugName}');
    return;
  }
  Timer(Duration(milliseconds: 1), () {
    Isolate.spawn(level, [port, depth - 1], debugName: 'level ${depth - 1}');
  });
}

void main() async {
  final port = ReceivePort();
  await Isolate.spawn(level, [port.sendPort, 3]);
  print(await port.first);
}
''',
  'what isolates are given': r'''
import 'dart:isolate';

class Holder {
  final List<int> values;
  Holder(this.values);
}

void main() async {
  final port = ReceivePort();
  final messages = port.asBroadcastStream();
  final holder = Holder([1, 2, 3]);
  final total = 10;
  await Isolate.spawn((SendPort port) {
    holder.values.add(4);
    port.send([holder.values, total, holder.values.length]);
  }, port.sendPort);
  print(await messages.first);
  print(holder.values);

  final unsendable = ReceivePort();
  try {
    await Isolate.spawn(print, unsendable);
  } on ArgumentError catch (error) {
    print((error.message as String).startsWith('Illegal argument'));
  }
  unsendable.close();

  final map = {for (var i = 0; i < 100; i++) 'key $i': i};
  await Isolate.spawn((List message) {
    final [SendPort port, Map<String, int> map] = message as List;
    port.send(map.values.fold<int>(0, (a, b) => a + b));
  }, [port.sendPort, map]);
  print(await messages.first);
  port.close();
}
''',
};
