class Link(final int value, final Link? previous);

void main(List<String> arguments) {
  if (arguments.length != 2 ||
      arguments[0] != 'standalone' ||
      arguments[1] != '中文🙂') {
    throw 'Incorrect process arguments.';
  }
  Link? head;
  for (var i = 0; i < 4000; i++) {
    head = Link(i, head);
  }
  var sum = 0;
  while (head != null) {
    sum += head.value;
    head = head.previous;
  }
  if (sum != 7998000) throw 'Incorrect live object chain.';
}
