import 'arguments.dart' as check;

Future<void> main(
  List<String> arguments,
  Object? message, [
  int sentinel = 73,
]) async {
  if (message != null || sentinel != 73) throw StateError('Main call shape.');
  final original = arguments;
  await Future<void>.delayed(Duration.zero);
  for (var i = 0; i < 40000; i++) {
    final storage = <String>['temporary $i'];
    if (storage.length != 1) throw StateError('Storage.');
  }
  if (!identical(original, arguments)) throw StateError('Argument identity.');
  check.main(arguments);
}
