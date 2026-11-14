class Link(final Link? previous, final int value);

Link append(Link? previous, int value) => Link(previous, value);

int factoryLoop(int count) {
  Link? head;
  for (var index = 0; index < count; index++) {
    head = append(head, index);
  }
  return head?.value ?? -1;
}

int previousIteration(int count) {
  var previous = -1;
  var same = 0;
  for (var index = 0; index < count; index++) {
    final current = index + 1;
    if (previous == current) same++;
    previous = current;
  }
  return same;
}

int preservedCaller(int count) {
  final preserved = append(null, 71);
  var head = append(null, -1);
  for (var index = 0; index < count; index++) {
    head = append(head, index);
  }
  return preserved.value + head.value;
}

int chainSum(int count) {
  Link? head;
  for (var index = 0; index < count; index++) {
    head = append(head, index);
  }
  var sum = 0;
  while (head != null) {
    sum += head.value;
    head = head.previous;
  }
  return sum;
}

int recursiveStored(int count) {
  final saved = append(null, count);
  if (count <= 0) return saved.value;
  final nested = recursiveStored(count - 1);
  return saved.value + nested;
}
