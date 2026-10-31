part of '../nodes.dart';

/// A directive or declaration written at the top level of a source file.
sealed class CompilationUnitMember implements AstNode;

/// The syntax of one complete source snapshot.
///
/// The range covers the whole file, including surrounding trivia. Members
/// retain their source order, including misplaced directives in erroneous
/// input. Construction does not load imports or validate library structure.
final class CompilationUnit({
  required super.source,

  /// The written script tag, or `null` when absent.
  final ScriptTag? scriptTag,

  required List<CompilationUnitMember> members,
}) extends AstNode {
  /// The directives and declarations, copied into an unmodifiable list.
  final List<CompilationUnitMember> members = _freeze(members);

  this : super(start: 0, end: source.length) {
    _checkChildren(this);
  }

  @override
  int get childCount => (scriptTag == null ? 0 : 1) + members.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (scriptTag != null) {
      if (index == 0) return scriptTag!;
      index--;
    }
    return members[index];
  }
}

/// A script tag beginning with `#!`, excluding its terminating line break.
final class ScriptTag({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;
