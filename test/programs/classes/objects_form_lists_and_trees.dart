class Node {
  final int value;
  Node? left, right;
  Node(this.value);
}

Node insert(Node? at, int value) {
  if (at == null) return Node(value);
  if (value < at.value)
    at.left = insert(at.left, value);
  else
    at.right = insert(at.right, value);
  return at;
}

void walk(Node? at) {
  if (at == null) return;
  walk(at.left);
  number(at.value);
  walk(at.right);
}

void main() {
  Node? root;
  var seed = 7;
  for (var i = 0; i < 40; i++) {
    seed = seed * 37 % 101;
    root = insert(root, seed);
  }
  walk(root);
  // expect: 2
  // expect: 2
  // expect: 3
  // expect: 3
  // expect: 7
  // expect: 10
  // expect: 10
  // expect: 11
  // expect: 11
  // expect: 15
  // expect: 15
  // expect: 32
  // expect: 35
  // expect: 35
  // expect: 38
  // expect: 41
  // expect: 41
  // expect: 48
  // expect: 50
  // expect: 50
  // expect: 55
  // expect: 55
  // expect: 57
  // expect: 57
  // expect: 59
  // expect: 61
  // expect: 61
  // expect: 62
  // expect: 67
  // expect: 67
  // expect: 72
  // expect: 73
  // expect: 74
  // expect: 74
  // expect: 75
  // expect: 83
  // expect: 83
  // expect: 89
  // expect: 89
  // expect: 93
}

void number(int n) => print(n);
