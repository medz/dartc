import 'other.dart' deferred as o hide X;

Object? used() => o.f();
Future<void> load() => o.loadLibrary();
