// Many objects that are soon not needed.
class Tree {
  final Tree? left, right;
  Tree(this.left, this.right);
}

Tree make(int depth) => depth == 0
    ? Tree(null, null)
    : Tree(make(depth - 1), make(depth - 1));

int count(Tree tree) {
  final left = tree.left, right = tree.right;
  return left == null || right == null ? 1 : 1 + count(left) + count(right);
}

void main() {
  const most = 16;
  final kept = make(most);
  for (var depth = 4; depth <= most; depth += 4) {
    var sum = 0;
    for (var i = 0; i < 1 << (most - depth + 4); i++) {
      sum += count(make(depth));
    }
    print('$depth $sum');
  }
  print(count(kept));
}
