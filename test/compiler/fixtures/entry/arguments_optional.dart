import 'arguments.dart' as check;

void main([
  Iterable<String>? arguments,
  Object? message = 'default',
  int sentinel = 73,
]) {
  if (message != null || sentinel != 73) throw StateError('Main defaults.');
  check.main(arguments! as List<String>);
}
