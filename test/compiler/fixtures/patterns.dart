import 'dart:convert';

import '../../frontend/lowering/fixtures/collection_patterns.dart'
    as collection;
import '../../frontend/lowering/fixtures/object_patterns.dart' as object;
import '../../frontend/lowering/fixtures/effects.dart';

void main(List<String> args) {
  final cases = switch (args.single) {
    'collections' => <(String, int Function(int), List<int>)>[
      ('listShapes', collection.listShapes, [0, 1, 2, 4]),
      ('listWildcards', collection.listWildcards, [0, 1, 2, 3]),
      ('listOrder', collection.listOrder, [0, 1, 2, 3]),
      ('listCaches', collection.listCaches, [0, 1, 3]),
      ('listRestCopy', collection.listRestCopy, [0, 1]),
      ('listNullChecks', collection.listNullChecks, [0, 1, 3]),
      ('listCastFailure', collection.listCastFailure, [0, 1]),
      ('mapOrder', collection.mapOrder, [0, 1, 3]),
      ('mapFailure', collection.mapFailure, [0, 1, 2]),
      ('mapNonnullable', collection.mapNonnullable, [0, 1]),
      ('mapCaches', collection.mapCaches, [0, 1, 3]),
      ('inconsistentMap', collection.inconsistentMap, [0, 1, 2, 3]),
      ('assignmentAtomic', collection.assignmentAtomic, [0, 1, 3]),
      ('nestedAssignmentAtomic', collection.nestedAssignmentAtomic, [0, 1]),
      ('castAssignmentAtomic', collection.castAssignmentAtomic, [0, 1]),
      ('contextualDeclarations', collection.contextualDeclarations, [0, 1, 2]),
      (
        'contextualNestedAssignment',
        collection.contextualNestedAssignment,
        [0, 1],
      ),
      ('contextualMapAssignment', collection.contextualMapAssignment, [0, 1]),
      ('contextualRecordFields', collection.contextualRecordFields, [0, 1]),
      ('genericPatterns', collection.genericPatterns, [0, 1, 2]),
      ('dynamicCollectionTypes', collection.dynamicCollectionTypes, [0, 1]),
      ('mismatchedCollections', collection.mismatchedCollections, [0, 1, 2]),
      ('patternLoops', collection.patternLoops, [0, 1]),
      (
        'uncontextualPatternIteration',
        collection.uncontextualPatternIteration,
        [0],
      ),
    ],
    'objects' => <(String, int Function(int), List<int>)>[
      (
        'orderedBase',
        (seed) => object.orderedObject(seed, false),
        [-12, -1, 0, 1],
      ),
      (
        'orderedDerived',
        (seed) => object.orderedObject(seed, true),
        [-12, -1, 0, 1],
      ),
      ('wildcardObject', object.wildcardObject, [-1, 0, 1]),
      ('nullableObject', object.nullableObject, [-1, 0, 1]),
      ('assignObject', object.assignObject, [-12, -1, 0, 1]),
      ('methodObject', object.methodObject, [0, 1]),
      ('alternativeObject', object.alternativeObject, [0, 1]),
      ('nestedAlternativeObject', object.nestedAlternativeObject, [0, 1]),
      ('switchObject', object.switchObject, [0, 1]),
      ('switchStatementObject', object.switchStatementObject, [0, 1]),
      ('castObject', object.castObject, [0, 1]),
      ('nestedGetterObject', object.nestedGetterObject, [0, 1]),
      ('guardedMutationObject', object.guardedMutationObject, [0, 1]),
      ('narrowedGetterObject', object.narrowedGetterObject, [0, 1]),
      ('separateMatchesObject', object.separateMatchesObject, [0, 1]),
      ('relationalAndObject', object.relationalAndObject, [0, 1]),
      ('relationalOrObject', object.relationalOrObject, [0, 1]),
      ('equalityComplementObject', object.equalityComplementObject, [0, 1]),
      ('distinctRelationalObject', object.distinctRelationalObject, [0, 1, 4]),
      ('guardedRelationalObject', object.guardedRelationalObject, [0, 1]),
      ('canonicalRelationalObject', object.canonicalRelationalObject, [1, 4]),
      ('receiverPathsObject', object.receiverPathsObject, [0, 1]),
    ],
    _ => throw ArgumentError(args),
  };
  for (final (name, run, inputs) in cases) {
    for (final input in inputs) {
      calls.clear();
      int? value;
      Object? error;
      try {
        value = run(input);
      } on TypeError {
        error = 'type';
      } on StateError {
        error = 'state';
      } on int catch (failure) {
        error = failure;
      }
      print(jsonEncode([name, input, value, error, calls]));
    }
  }
}
