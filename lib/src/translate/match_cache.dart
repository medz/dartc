import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';

/// What the patterns of one statement or expression get from the value that
/// they match, each of which is evaluated once.
final class MatchCache(
  final FunctionBuilder _builder,
  final Conversions _conversions,
) {
  final _values = <String, (Temporary value, Temporary isSet)>{};

  /// The variables that are kept, which every way through the patterns needs.
  List<Temporary> get variables => [
    for (final (value, isSet) in _values.values) ...[value, isSet],
  ];

  /// Prepares to keep what is told by one of [keys].
  void prepare(Iterable<String> keys) {
    for (final key in keys) {
      final value = Temporary(), isSet = Temporary();
      _builder
        ..declare(value, .reference)
        ..assign(value, _builder.add(HirNull()))
        ..declare(isSet, .boolean)
        ..assign(isSet, _builder.add(HirConst(false)));
      _values[key] = (value, isSet);
    }
  }

  /// What [compute] gives, represented as [type].
  ///
  /// It is evaluated only if what [key] tells was not.
  HirValue read(
    AstNode node,
    String key,
    HirType type,
    HirValue Function() compute,
  ) {
    final found = _values[key];
    if (found == null) return _conversions.coerce(compute(), type);
    final (value, isSet) = found;
    final exit = _builder.joinAll(node, const [], [value, isSet]);
    _builder.branch(_builder.read(isSet), () => _builder.jump(exit), () {
      final given = _conversions.coerce(compute(), .reference);
      _builder
        ..assign(value, given)
        ..assign(isSet, _builder.add(HirConst(true)))
        ..jump(exit);
    });
    _builder.enter(exit);
    return _conversions.coerce(_builder.read(value), type);
  }
}
