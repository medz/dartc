import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

/// What functions do that are not done when they return.
enum CoroutineKind() {
  async,
  asyncStar,
  syncStar;

  /// The kind of functions with [body], or null for those that run at once.
  static CoroutineKind? of(FunctionBody body) =>
      switch ((body.isAsynchronous, body.isGenerator)) {
        (true, false) => async,
        (true, true) => asyncStar,
        (false, true) => syncStar,
        _ => null,
      };
}

/// A function translated that can be left in the middle.
final class Coroutine(
  final CoroutineKind kind,

  /// What it calls where it can be left.
  final HirFunction suspend,

  /// What the runtime knows it by.
  final HirValue state,
);
