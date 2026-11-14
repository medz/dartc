import '../../frontend/lowering/fixtures/constants.dart' as values;
import '../../frontend/lowering/fixtures/generic_constants.dart' as generic;
import 'extension_types.dart' show observe;

bool crossLibraryConstants() =>
    identical(
      const values.Box<int Function(int)>(values.identity<int>),
      values.functionBox,
    ) &&
    identical(const <int>[3, 1, 2], values.listConstant) &&
    identical(const <int>{3, 1, 2}, values.setConstant) &&
    identical(const <int, int>{3: 30, 1: 10, 2: 20}, values.mapConstant);

void main(List<String> args) {
  switch (args.single) {
    case 'identity':
      for (final (name, run) in <(String, Object? Function())>[
        ('rootObjectIdentity', values.rootObjectIdentity),
        ('importedConstructorAlias', values.importedConstructorAlias),
        ('collectionTypes', values.collectionTypes),
        ('collectionOrder', values.collectionOrder),
        ('collectionEmptyNested', values.collectionEmptyNested),
        ('collectionControl', values.collectionControl),
        ('objectFields', values.objectFields),
        ('canonicalObjects', values.canonicalObjects),
        ('redirectedAndDefaults', values.redirectedAndDefaults),
        ('equalityVersusIdentity', values.equalityVersusIdentity),
        ('canonicalCollections', values.canonicalCollections),
        ('widenedRecordCanonicalization', values.widenedRecordCanonicalization),
        ('orderedCanonicalCollections', values.orderedCanonicalCollections),
        ('listReadBounds', values.listReadBounds),
        ('crossLibraryConstants', crossLibraryConstants),
      ]) {
        observe(name, run);
      }
      for (final input in [0, 1, 2, 3, 4]) {
        observe(
          'constantEqualityPattern',
          () => values.constantEqualityPattern(input),
          input,
        );
      }
      for (final derived in [false, true]) {
        observe(
          'constantPatterns',
          () => values.constantPatterns(derived),
          derived,
        );
      }
      for (final input in [-1, 0, 7]) {
        observe(
          'embeddedFunctions',
          () => values.embeddedFunctions(input),
          input,
        );
        observe(
          'embeddedAliasConstructors',
          () => values.embeddedAliasConstructors(input),
          input,
        );
      }
    case 'mutation':
      for (final (name, run, count) in <(String, int Function(int), int)>[
        ('listMutation', values.listMutation, 6),
        ('setMutation', values.setMutation, 4),
        ('mapMutation', values.mapMutation, 4),
      ]) {
        for (var operation = 0; operation < count; operation++) {
          observe(name, () => run(operation), operation);
        }
      }
      for (final kind in [0, 1, 2]) {
        for (final immutable in [false, true]) {
          for (final custom in [false, true]) {
            observe(
              'addAllSourceType',
              () => values.addAllSourceType(kind, immutable, custom),
              [kind, immutable, custom],
            );
          }
        }
      }
      for (final fail in [false, true]) {
        for (final asSet in [false, true]) {
          observe(
            'literalDynamicSpread',
            () => values.literalDynamicSpread(fail, asSet),
            [fail, asSet],
          );
        }
      }
    case 'generic':
      for (final (name, run) in <(String, int Function(int))>[
        ('genericConstantCalls', generic.genericConstantCalls),
        ('genericConstantConstructors', generic.genericConstantConstructors),
        ('genericAliasConstants', generic.genericAliasConstants),
      ]) {
        for (final input in [-1, 0, 5]) {
          observe(name, () => run(input), input);
        }
      }
      for (final input in <Object>[1, 'one', true]) {
        observe(
          'genericConstantChecks',
          () => generic.genericConstantChecks(input),
          input,
        );
      }
      observe('genericConstantIdentity', generic.genericConstantIdentity);
      observe(
        'genericAliasConstantIdentity',
        generic.genericAliasConstantIdentity,
      );
      for (final (name, run) in <(String, int Function(bool))>[
        ('genericConstantPattern', generic.genericConstantPattern),
        ('genericConstructorPattern', generic.genericConstructorPattern),
        ('genericAliasConstantPattern', generic.genericAliasConstantPattern),
        ('genericInlineAliasPattern', generic.genericInlineAliasPattern),
      ]) {
        for (final first in [false, true]) {
          observe(name, () => run(first), first);
        }
      }
  }
}
