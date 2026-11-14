import '../../frontend/lowering/fixtures/mixins.dart' as basic;
import '../../frontend/lowering/fixtures/mixin_application_state.dart' as state;
import '../../frontend/lowering/fixtures/mixin_type_environments.dart' as types;
import '../../frontend/lowering/fixtures/mixin_composition.dart' as composition;
import 'extension_types.dart' show observe;

int retainedGenerator() {
  final value = composition.CompositionLast();
  final iterator = value.values().iterator;
  if (!iterator.moveNext()) throw StateError('Missing first value');
  var result = iterator.current;
  for (var index = 0; index < 2000; index++) {
    final garbage = List<String>.filled(64, index.toString());
    if (garbage.first.isEmpty) throw StateError('Invalid pressure value');
  }
  while (iterator.moveNext()) {
    result = result * 10 + iterator.current;
  }
  return result;
}

void main(List<String> args) {
  final cases = switch (args.single) {
    'basic' => <(String, Object? Function())>[
      ('overrideOrder', basic.overrideOrder),
      ('superMembers', basic.superMembers),
      ('interfaceDispatch', basic.interfaceDispatch),
      ('dynamicMembers', basic.dynamicMembers),
      ('tearoffs', basic.tearoffs),
      ('aliasConstructors', basic.aliasConstructors),
      ('aliasConstructorTearoffs', basic.aliasConstructorTearoffs),
      ('privateMembers', basic.privateMembers),
      ('missingMembers', basic.missingMembers),
      ('mixinClass', basic.mixinClass),
    ],
    'state' => <(String, Object? Function())>[
      ('constraintReceiverView', state.constraintReceiverView),
      ('constructorFieldEffects', state.constructorFieldEffects),
      ('independentState', state.independentState),
      ('independentStateWrites', state.independentStateWrites),
      ('independentLazyState', state.independentLazyState),
      (
        'lazyAssignmentSkipsOnlyOwnInitializer',
        state.lazyAssignmentSkipsOnlyOwnInitializer,
      ),
      ('independentLateFinalWrites', state.independentLateFinalWrites),
      ('lexicalSuperCalls', state.lexicalSuperCalls),
      ('lexicalSuperTearoffs', state.lexicalSuperTearoffs),
      ('lexicalSuperEscapedClosures', state.lexicalSuperEscapedClosures),
      ('mixinClassLexicalSuper', state.mixinClassLexicalSuper),
      ('privateClosureProvenance', state.privateClosureProvenance),
    ],
    'types' => <(String, Object? Function())>[
      ('genericOwners', types.genericOwners),
      ('genericAliases', types.genericAliases),
      ('genericMixins', types.genericMixins),
      ('genericSuper', types.genericSuper),
      ('covariance', types.covariance),
      ('abstractMembers', types.abstractMembers),
      ('inheritedCovariance', types.inheritedCovariance),
      ('constants', types.constants),
      ('nested', types.nested),
    ],
    _ => <(String, Object? Function())>[
      ('composedGenerators', composition.composedGenerators),
      ('composedObjectMembers', composition.composedObjectMembers),
      ('composedUnionTypes', composition.composedUnionTypes),
      ('retainedGenerator', retainedGenerator),
    ],
  };
  for (final (name, run) in cases) {
    observe(name, run);
  }
  if (args.single == 'state') {
    for (final (name, run) in [
      ('lateFinalSecondWrite', state.lateFinalSecondWrite),
      ('lateReadDoesNotBorrowOtherSlot', state.lateReadDoesNotBorrowOtherSlot),
    ]) {
      observe(name, () {
        try {
          return run();
        } on Error catch (error) {
          return error.toString().startsWith('LateInitializationError:');
        }
      });
    }
  }
}
