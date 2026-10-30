import 'nodes.dart';

/// Visits [root] and its descendants in depth-first source order.
///
/// The traversal is lazy and does not recurse on the Dart call stack. Its
/// temporary storage grows with pending ancestor branches, not the width of
/// a node. Each iteration starts a fresh traversal. Shared nodes are visited
/// once for each occurrence in the tree.
Iterable<AstNode> walk(AstNode root) sync* {
  var node = root;
  yield node;
  if (node.childCount == 0) return;
  // Entries are a remaining binary child or a cursor over wider siblings.
  final pending = <Object>[];
  while (node.childCount != 0 || pending.isNotEmpty) {
    final count = node.childCount;
    if (count != 0) {
      if (count == 2) {
        pending.add(node.childAt(1));
      } else if (count > 2) {
        pending.add(_SiblingCursor(node));
      }
      node = node.childAt(0);
    } else {
      final last = pending.last;
      if (last is AstNode) {
        node = last;
        pending.removeLast();
      } else {
        final siblings = last as _SiblingCursor;
        node = siblings.parent.childAt(siblings.next++);
        if (siblings.next == siblings.parent.childCount) pending.removeLast();
      }
    }
    yield node;
  }
}

final class _SiblingCursor(final AstNode parent) {
  int next = 1;
}
