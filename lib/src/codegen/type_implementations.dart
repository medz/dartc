import 'package:dartc/ir.dart';

import 'type_relations.dart';
import 'type_runtime.dart';
import 'type_values.dart';

/// Owns type descriptors and executable projections for one compilation.
///
/// Reuse this owner across graph and layout revisions. New declarations retain
/// existing shape numbers, call targets and declaration-owned projection bodies.
/// Generated definitions are dependencies of actual calls, never extra roots.
final class TypeImplementations({
  TypeRuntime? runtime,
  Iterable<ClassType> declarations = const [],
  ClassType? recordStorage,
}) {
  final values = TypeValues(runtime);
  late final TypeRelations relations;

  this {
    relations = TypeRelations(
      values,
      declarations,
      recordStorage: recordStorage,
    );
  }

  /// Changes when any descriptor identity, declaration or executable entry grows.
  ///
  /// Reading generated bodies can demand further entries. Capture the revision
  /// after consuming them; facts and selection from an earlier revision expire.
  int get revision => values.revision + relations.revision;

  /// Moves source lookups to the same entries in the current verified graph.
  void rebind(TypeRuntime? current) => values.rebind(current);

  /// Extends the same compilation without creating new entry points.
  bool extend(Iterable<ClassType> declarations, {ClassType? recordStorage}) =>
      relations.extend(declarations, recordStorage: recordStorage);

  /// Current typed bodies, including templates demanded by nominal projections.
  Iterable<IrFunction> get functions {
    final projections = relations.functions.toList();
    return [...projections, ...values.functions];
  }
}
