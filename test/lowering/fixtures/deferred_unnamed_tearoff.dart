import 'deferred_library.dart' deferred as p;

Future<int> create() async {
  await p.loadLibrary();
  final make = p.C.new;
  return make(42).value;
}
