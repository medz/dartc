class Link(final int value, final Link? previous);

void main() {
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
