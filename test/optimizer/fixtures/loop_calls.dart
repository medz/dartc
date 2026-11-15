class Link(final Link? previous, final int value);

class CallbackLink(final CallbackLink? previous, final int Function() value);

class MutableBox(var int value);

class BoxHolder(var MutableBox value);

int detachThenLoop(BoxHolder holder, int count) {
  holder.value.value = 73;
  holder.value = MutableBox(-1);
  var sum = 0;
  for (var i = 0; i < count; i++) {
    final int current;
    if (i.isEven) {
      current = i;
    } else {
      current = -i;
    }
    sum += current;
  }
  return sum;
}

int retainedCallerAlias(int count) {
  final original = MutableBox(0);
  final holder = BoxHolder(original);
  final result = detachThenLoop(holder, count);
  return original.value + result;
}

int retainedIterations(int count) {
  CallbackLink? head;
  for (var i = 0; i < count; i++) {
    late int value;
    value = i;
    head = CallbackLink(head, () => value);
  }
  var result = 0;
  while (head != null) {
    result = result * 3 + head.value();
    head = head.previous;
  }
  return result;
}

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

int pairedFactories(int count) {
  Link? left, right;
  for (var index = 0; index < count; index++) {
    left = append(left, index);
    right = append(right, index + 100);
  }
  var sum = 0;
  while (left != null && right != null) {
    sum += right.value - left.value;
    left = left.previous;
    right = right.previous;
  }
  return sum;
}

T invoke<T>(T Function() action) => action();

int nestedCallbacks(int value) => invoke(() => invoke(() => value + 1));

int recursiveCallback(int count) =>
    count <= 0 ? 0 : invoke(() => recursiveCallback(count - 1)) + 1;

int nestedThrow(int value) => invoke(() {
  try {
    return invoke<int>(() => throw value);
  } on int catch (error) {
    return error + 2;
  }
});
