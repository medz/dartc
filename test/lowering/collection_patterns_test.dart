import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/collection_patterns.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('collection_patterns');
  });

  test('sublist preserves an omitted end and an explicitly passed null', () {
    fixture.compare('sublistArguments', [], sdk.sublistArguments);
    final function = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'sublistArguments',
    );
    final calls = function.blocks
        .expand((b) => b.instructions)
        .whereType<ListSublist>();
    expect(calls.map((call) => call.inputs.length), [2, 3, 3]);
  });

  for (final (name, function, inputs)
      in <(String, int Function(int), List<int>)>[
        ('contextualDeclarations', sdk.contextualDeclarations, [0, 1, 2]),
        ('contextualNestedAssignment', sdk.contextualNestedAssignment, [0, 1]),
        ('contextualMapAssignment', sdk.contextualMapAssignment, [0, 1]),
        ('uncontextualPatternIteration', sdk.uncontextualPatternIteration, [0]),
        ('contextualRecordFields', sdk.contextualRecordFields, [0, 1]),
        ('inconsistentMap', sdk.inconsistentMap, [0, 1, 2, 3]),
        ('negativeLength', sdk.negativeLength, [-1, 0, 1]),
        ('listTypedRestWildcard', sdk.listTypedRestWildcard, [0, 1]),
        ('mapLogical', sdk.mapLogical, [0, 1, 3]),
        ('listNullChecks', sdk.listNullChecks, [0, 1, 3]),
        ('listCastFailure', sdk.listCastFailure, [0, 1]),
        ('nestedAssignmentAtomic', sdk.nestedAssignmentAtomic, [0, 1]),
        ('genericPatterns', sdk.genericPatterns, [0, 1, 2]),
        ('dynamicCollectionTypes', sdk.dynamicCollectionTypes, [0, 1, 2]),
        ('mismatchedCollections', sdk.mismatchedCollections, [0, 1, 2]),
        ('castAssignmentAtomic', sdk.castAssignmentAtomic, [0, 1, 2]),
        ('listShapes', sdk.listShapes, [0, 1, 2, 4]),
        ('listWildcards', sdk.listWildcards, [0, 1, 2, 3]),
        ('listOrder', sdk.listOrder, [0, 1, 2, 3]),
        ('listTailRest', sdk.listTailRest, [0, 1, 2, 3]),
        ('listCaches', sdk.listCaches, [0, 1, 3]),
        ('listLogical', sdk.listLogical, [0, 1, 3]),
        ('listPaths', sdk.listPaths, [0, 1, 3]),
        ('listRestCopy', sdk.listRestCopy, [0, 1, 3]),
        ('nestedCollections', sdk.nestedCollections, [0, 1, 3]),
        ('mapShapes', sdk.mapShapes, [0, 1, 3]),
        ('mapOrder', sdk.mapOrder, [0, 1, 3]),
        ('mapFailure', sdk.mapFailure, [0, 1, 2]),
        ('mapNonnullable', sdk.mapNonnullable, [0, 1, 3]),
        ('mapCaches', sdk.mapCaches, [0, 1, 3]),
        ('declarations', sdk.declarations, [0, 1, 3]),
        ('assignmentAtomic', sdk.assignmentAtomic, [0, 1, 3]),
        ('patternLoops', sdk.patternLoops, [0, 1, 3]),
        ('erasedPatterns', sdk.erasedPatterns, [0, 1]),
      ]) {
    test('$name matches SDK results, exceptions and effect order', () {
      for (final input in inputs) {
        fixture.compare(name, [input], () => function(input));
      }
    });
  }
}
