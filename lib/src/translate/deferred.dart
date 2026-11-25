import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'deferred_scope.dart';
import 'scope.dart';

/// The names of libraries that the program loads itself. All are there from the
/// start, but cannot be used before.
final class DeferredTable(final ProgramScope _scope, final SourceUnit _unit)
    implements DeferredScope {
  final _prefixes = <PrefixElement, (HirGlobal, HirFunction)>{};
  final _loaders = <PrefixElement, HirConstObject>{};

  /// Where the objects for the names are kept.
  Iterable<HirGlobal> get globals => _prefixes.values.map((known) => known.$1);

  @override
  HirValue prefix(FunctionBuilder builder, PrefixElement prefix) {
    final (_, function) = _prefixes[prefix] ??= _make(prefix);
    return builder.call(HirCall(function, const []))!;
  }

  (HirGlobal, HirFunction) _make(PrefixElement prefix) {
    final global = HirGlobal(prefix.displayName, .reference, null);
    final function = HirFunction(prefix.displayName, const [], .reference);
    _scope.addLocalFunction(function);
    final builder = FunctionBuilder(_unit, function, const []);
    final known = builder.add(HirLoadGlobal(global));
    builder.branch(Conversions(_scope, builder).isNull(known), () {
      final text = builder.add(_scope.text(prefix.displayName));
      final made = builder.call(
        HirCall(_scope.runtime('deferredPrefix'), [text]),
      )!;
      builder
        ..add(HirStoreGlobal(global, made))
        ..end(HirReturn(made));
    }, () => builder.end(HirReturn(known)));
    builder.finish();
    return (global, function);
  }

  @override
  HirValue load(FunctionBuilder builder, PrefixElement prefix) => builder.call(
    HirCall(_scope.runtime('loadLibrary'), [this.prefix(builder, prefix)]),
  )!;

  @override
  HirValue loader(
    FunctionBuilder builder,
    PrefixElement prefix,
    ExecutableElement element,
  ) =>
      builder.add(HirStatic(_loaders[prefix] ??= _makeLoader(prefix, element)));

  HirConstObject _makeLoader(PrefixElement prefix, ExecutableElement element) {
    final name = '_#loadLibrary_${prefix.displayName}';
    final class_ = HirClass(name, null, const []);
    final function = HirFunction(name, const [.reference], .reference);
    _scope
      ..addLocalFunction(function)
      ..addClosure(
        Closure(
          class_,
          const [],
          () => function,
          (_, self) => [self],
          typeValue: (builder) => _scope.typeValue(builder, element.type)!,
          name: name,
          text: " from Function '$name': static.",
        ),
      );
    final builder = FunctionBuilder(_unit, function, const []);
    builder
      ..end(HirReturn(load(builder, prefix)))
      ..finish();
    return HirConstObject(class_, const {});
  }
}

/// Translates what uses of libraries that the program loads itself do first.
final class DeferredTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  /// Checks that the library is loaded that [node] uses, if it is such a one.
  /// Gives the value of [node] if it loads that.
  HirValue? use(Expression node) {
    final prefix = _prefixOf(node);
    if (prefix == null || !prefix.fragments.any((f) => f.isDeferred)) {
      return null;
    }
    final table = _scope.deferred;
    switch (node) {
      case MethodInvocation(
            methodName: SimpleIdentifier(
              :final TopLevelFunctionElement element,
            ),
          )
          when _isLoader(element):
        return table.load(_builder, prefix);
      case PrefixedIdentifier(
            identifier: SimpleIdentifier(
              :final TopLevelFunctionElement element,
            ),
          )
          when _isLoader(element):
        return table.loader(_builder, prefix, element);
    }
    _builder.call(
      HirCall(_scope.runtime('checkLoaded'), [table.prefix(_builder, prefix)]),
    );
    return null;
  }

  static bool _isLoader(TopLevelFunctionElement element) =>
      element == element.library.loadLibraryFunction;

  static PrefixElement? _prefixOf(Expression node) => switch (node) {
    PrefixedIdentifier(:final prefix) => _prefix(prefix),
    PropertyAccess(:final target?) ||
    MethodInvocation(:final target?) => _prefixOfTarget(target),
    AssignmentExpression(:final leftHandSide) => _prefixOf(leftHandSide),
    PrefixExpression(operand: final Expression place) ||
    PostfixExpression(operand: final Expression place) => _prefixOfPlace(place),
    InstanceCreationExpression(:final constructorName) ||
    ConstructorReference(
      :final constructorName,
    ) => _element(constructorName.type.importPrefix?.element),
    TypeLiteral(type: NamedType(:final importPrefix)) => _element(
      importPrefix?.element,
    ),
    FunctionReference(:final function) => _prefixOf(function),
    _ => null,
  };

  /// Operators that assign read a place themselves.
  static PrefixElement? _prefixOfPlace(Expression place) => switch (place) {
    PrefixedIdentifier() || PropertyAccess() => _prefixOf(place),
    _ => null,
  };

  static PrefixElement? _prefixOfTarget(Expression target) => switch (target) {
    SimpleIdentifier() => _prefix(target),
    // A class or the like, which is not evaluated.
    PrefixedIdentifier(
      :final prefix,
      identifier: SimpleIdentifier(
        element: InstanceElement() || TypeAliasElement(),
      ),
    ) =>
      _prefix(prefix),
    _ => null,
  };

  static PrefixElement? _prefix(SimpleIdentifier node) =>
      _element(node.element);

  static PrefixElement? _element(Element? element) =>
      element is PrefixElement ? element : null;
}
