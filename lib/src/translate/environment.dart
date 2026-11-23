import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';

/// What a closure keeps of the function that creates it, as its own fields.
final class Environment._(
  final FunctionBuilder _outer,
  final Captures _captures,
  final Map<Element, HirField> _variables,
  final Map<Element, HirField> _lists,
  final HirField? _receiver,
) {
  /// What the closure [node] keeps, which calls itself [name].
  factory of(
    FunctionBuilder outer,
    AstNode node,
    Captures captures, {
    Element? name,
  }) => Environment._(
    outer,
    captures,
    {
      for (final used in captures.usedBy(node))
        if (used != name)
          used: HirField(used.displayName, outer.rawTypeOf(used)!),
    },
    {
      for (final owner in outer.typeLists.keys)
        owner: HirField('types', .reference),
    },
    outer.receiver == null ? null : HirField('this', .reference),
  );

  List<HirField> get fields => [
    ?_receiver,
    ..._variables.values,
    ..._lists.values,
  ];

  /// Keeps it all in [object], where that is created.
  void store(HirValue object) {
    void keep(HirField field, HirValue value) =>
        _outer.add(HirStore(field, object, value));
    if (_receiver case final field?) keep(field, _outer.receiver!);
    _variables.forEach((used, field) => keep(field, _outer.raw(used)));
    _lists.forEach((owner, field) => keep(field, _outer.typeLists[owner]!));
  }

  /// Makes what types are made of known to [builder].
  void bindTypes(FunctionBuilder builder, HirValue object) {
    if (_receiver case final field?) {
      final receiver = builder.add(HirLoad(field, object));
      builder.setReceiver(receiver, _outer.level!);
    }
    _lists.forEach((owner, field) {
      builder.bindTypes(owner, builder.add(HirLoad(field, object)));
    });
  }

  /// Builds [function], which is given its closure first.
  FunctionBuilder build(
    HirFunction function,
    List<FormalParameterElement> parameters, {
    Element? typeOwner,
    DartType? returnType,
  }) {
    final builder = FunctionBuilder(
      _outer.unit,
      function,
      parameters,
      ownLevel: _outer.level,
      isClosure: true,
      typeOwner: typeOwner,
      returnType: returnType,
      captures: _captures,
      cellClass: _outer.cellClass,
      locals: _outer.locals,
    );
    final self = builder.inputs.first;
    bindTypes(builder, self);
    _variables.forEach((used, field) {
      final type = _outer.typeOf(used)!;
      builder.bind(used, builder.add(HirLoad(field, self)), type);
    });
    return builder;
  }
}
