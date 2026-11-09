import 'deferred_library.dart' deferred as p;
import 'deferred_library.dart' deferred as q;
import 'effects.dart';

int access(int action) {
  switch (action) {
    case 0:
      return p.add(tick(1));
    case 1:
      return p.value = tick(2);
    case 2:
      return p.C(tick(3)).value;
    case 3:
      return p.C.method(tick(4));
    case 4:
      final make = p.C.named;
      return make(tick(5)).value;
    case 5:
      return p.C == p.C ? 6 : 0;
    case 6:
      final function = p.add;
      return function(tick(7));
    case 7:
      return p.C.constant;
    case 8:
      return p.E(tick(9)).value;
    case 9:
      p.C.write = tick(10);
      return 10;
    case 10:
      return p.constant;
    case 11:
      return p.function(tick(11));
    case 12:
      return p.echo<int>(tick(12));
    case 13:
      return p.value += tick(14);
    case 14:
      return p.C.read;
    case 15:
      p.write = tick(15);
      return p.read;
    default:
      final method = p.C.method;
      return method(tick(16));
  }
}

String tryAccess(int action) {
  try {
    return '${access(action)}';
  } catch (_) {
    return 'blocked';
  }
}

Future<String> exercise() async {
  var result = '';
  for (var i = 0; i <= 16; i++) {
    result += '${tryAccess(i)}:';
  }
  final load = p.loadLibrary;
  result +=
      '${identical(load, p.loadLibrary)}:${identical(load, q.loadLibrary)}:';
  final pending = load();
  result += '${tryAccess(0)}:';
  await pending;
  for (var i = 0; i <= 16; i++) {
    result += '${tryAccess(i)}:';
  }
  try {
    result += '${q.add(tick(17))}:';
  } catch (_) {
    result += 'other-blocked:';
  }
  await p.loadLibrary();
  await q.loadLibrary();
  return '$result${q.add(tick(18))}';
}
