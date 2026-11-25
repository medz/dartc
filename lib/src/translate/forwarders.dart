import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'classes.dart';
import 'conversions.dart';
import 'levels.dart';
import 'scope.dart';
import 'types.dart';

/// The members that classes with a `noSuchMethod` do not implement, which call
/// that.
final class ForwarderTable(
  final ProgramScope _scope,
  final Declarations _declarations,
  final SourceUnit _unit,
) {
  final _functions = <(Level, ExecutableElement), HirFunction>{};

  Iterable<HirFunction> get functions => _functions.values;

  /// Does the work of [member] for objects of [level].
  HirFunction of(Level level, ExecutableElement member) =>
      _functions[(level, member)] ??= _make(level, member);

  HirFunction _make(Level level, ExecutableElement member) {
    Never reject(String what) => throw _declarations.unsupported(member, what);
    final isGeneric = member.typeParameters.isNotEmpty;
    final viewed = viewedAt(level, member), resultType = viewed.returnType;
    final hasResult = !hasNoResult(resultType);
    final function = HirFunction(
      '${level.element.displayName}.${member.displayName}',
      [
        .reference,
        if (isGeneric) .reference,
        for (final parameter in member.formalParameters)
          valueType(parameter.type) ??
              reject('a parameter of type ${parameter.type}'),
      ],
      hasResult
          ? valueType(member.returnType) ??
                reject('a result of type $resultType')
          : null,
    );
    final builder = FunctionBuilder(
      _unit,
      function,
      member.formalParameters,
      ownLevel: level,
      typeOwners: [if (isGeneric) member],
    );
    if (builder.typesOf(member) case final types?) {
      // As seen there, it has its own type parameters.
      builder.bindParameters(viewed.typeParameters, types);
    }
    final result = _call(builder, member, viewed);
    if (hasResult) {
      final conversions = Conversions(_scope, builder);
      final dynamic = conversions.types.dynamicType;
      final checked =
          conversions.cast(result, dynamic, resultType) ??
          reject('testing for $resultType');
      builder.end(HirReturn(conversions.coerce(checked, function.result!)));
    }
    builder.finish();
    return function;
  }

  HirValue _call(
    FunctionBuilder builder,
    ExecutableElement member,
    ExecutableElement viewed,
  ) {
    final conversions = Conversions(_scope, builder);
    HirValue given(FormalParameterElement parameter) =>
        conversions.coerce(builder.read(parameter), .reference);
    final parameters = member.formalParameters;
    final named = parameters.where((parameter) => parameter.isNamed);
    return callMissing(
      _scope,
      builder,
      builder.receiver!,
      switch (member) {
        GetterElement() => 1,
        SetterElement() => 2,
        _ => 0,
      },
      builder.add(_scope.text(member.lookupName!)),
      [
        for (final parameter in parameters)
          if (parameter.isPositional) given(parameter),
      ],
      {for (final parameter in named) parameter.name!: given(parameter)},
      types: member.typeParameters.isEmpty ? null : builder.typesOf(member),
      found: describeType(viewed.type),
    );
  }
}

/// [member] as objects of [level] have it.
ExecutableElement viewedAt(Level level, ExecutableElement member) {
  final owner = member.enclosingElement;
  for (final type in level.class_.allSupertypes) {
    if (type.element != owner || type.typeArguments.isEmpty) continue;
    return switch (member) {
          GetterElement() => type.getGetter(member.name!),
          SetterElement() => type.getSetter(member.name!),
          _ => type.getMethod(member.name!),
        } ??
        member;
  }
  return member;
}

/// Calls the `noSuchMethod` of [object] for a use of the member [name], which
/// is a method, a getter or a setter depending on [kind].
///
/// If objects have such a member, but not with these arguments, [found] says
/// what it takes.
HirValue callMissing(
  ProgramScope scope,
  FunctionBuilder builder,
  HirValue object,
  int kind,
  HirValue name,
  List<HirValue> positional,
  Map<String, HirValue> named, {
  HirValue? types,
  String? found,
}) {
  final dynamic = builder.library.typeProvider.dynamicType;
  return builder.call(
    HirCall(scope.runtime('missing'), [
      object,
      builder.add(HirConst(kind)),
      name,
      types ?? builder.add(HirNull()),
      scope.list(builder, dynamic, [...positional, ...named.values]),
      scope.list(builder, dynamic, [
        for (final name in named.keys) builder.add(scope.text(name)),
      ]),
      builder.add(found == null ? HirNull() : scope.text(found)),
    ]),
  )!;
}
