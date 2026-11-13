Future<void> main() async {
  // ignore: await_only_futures
  await 0;
  throw StateError('async main');
}
