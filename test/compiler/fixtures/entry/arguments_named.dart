void main({int sentinel = 73}) {
  if (sentinel != 73) throw StateError('Named main default.');
  print(sentinel);
}
