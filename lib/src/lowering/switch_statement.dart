import 'package:analyzer/dart/analysis/features.dart' show Feature;
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'expression.dart';
import 'function_context.dart';
import 'operators.dart';
import 'pattern.dart';

/// Routes matching case heads and labeled continues to their shared bodies.
void lowerSwitchStatement(
  FunctionContext context,
  ast.SwitchStatement statement,
  JumpTarget exit,
  Map<ast.AstNode, void Function()> continues,
  void Function(ast.Statement) lowerStatement,
) {
  final subject = lowerExpression(context, statement.expression);
  if (subject == null) return;
  final cache = PatternCache(context, [
    for (final member in statement.members)
      if (member is ast.SwitchPatternCase) member.guardedPattern.pattern,
  ]);
  final pending = <_CaseBody>[];
  _CaseBody? fallback;

  void emitBody(_CaseBody body, [Block? entry]) {
    context.inScope(() {
      if (entry != null) {
        for (final (i, variable) in body.variables.indexed) {
          final value = entry.parameters[i];
          context.declare(variable, value.type, value);
        }
      }
      for (final child in body.member.statements) {
        if (context.current == null) break;
        lowerStatement(child);
      }
    });
    exit.jump();
  }

  void reach(
    _CaseBody body, [
    Iterable<PatternVariableElement> bindings = const [],
  ]) {
    if (!body.shared) {
      emitBody(body);
      return;
    }
    final values = <PatternVariableElement, Value>{};
    for (final variable in bindings) {
      final shared = variable.join ?? variable;
      if (shared is JoinPatternVariableElement && !shared.isConsistent) {
        continue;
      }
      values[shared] = context.readLocal(variable);
    }
    if (body.entry == null) {
      body.variables = values.keys.toList();
      body.entry = exit.sibling([
        for (final v in body.variables) context.typeOf(v.type, body.member),
      ]);
      pending.add(body);
    }
    body.entry!.jump([for (final v in body.variables) values[v]!]);
  }

  final members = statement.members;
  final groups = <_CaseBody>[];
  for (var first = 0; first < members.length;) {
    var last = first;
    while (last + 1 < members.length && members[last].statements.isEmpty) {
      last++;
    }
    final body = _CaseBody(members[last], last, first != last);
    groups.add(body);
    for (var i = first; i <= last; i++) {
      final member = members[i];
      if (member.labels.isNotEmpty) {
        body.shared = true;
        continues[member] = () => reach(body);
      }
    }
    first = last + 1;
  }
  var i = 0;
  for (final body in groups) {
    while (i <= body.last) {
      final member = members[i++];
      if (context.current == null && member is! ast.SwitchDefault) continue;
      final next = JumpTarget(context);
      switch (member) {
        case ast.SwitchDefault():
          fallback = body;
          continue;
        case ast.SwitchPatternCase(:final guardedPattern):
          context.inScope(() {
            final bindings = matchGuarded(
              context,
              guardedPattern,
              subject,
              next,
              (e) => lowerExpression(context, e),
              cache,
            );
            if (context.current != null) reach(body, bindings);
          });
        case ast.SwitchCase(:final expression):
          final constant = context.bindings.constantValue(
            expression.computeConstantValue()?.value,
            context.unit,
            expression,
          );
          context.guard(lowerEquality(context, constant, subject), next);
          if (context.current != null) reach(body);
      }
      next.enter();
    }
  }
  if (context.current != null) {
    if (fallback != null) {
      reach(fallback);
    } else if (context.unit.unit.featureSet.isEnabled(Feature.patterns) &&
        requiresExhaustiveSwitch(statement.expression.staticType!)) {
      context.exhaustivenessFailure();
    } else {
      exit.jump();
    }
  }

  // A backward continue can make a previously unmatched body reachable.
  for (var i = 0; i < pending.length; i++) {
    final body = pending[i];
    emitBody(body, body.entry!.enter()!);
  }
  for (final member in members) {
    if (member.labels.isNotEmpty) continues.remove(member);
  }
}

final class _CaseBody(
  final ast.SwitchMember member,
  final int last,
  var bool shared,
) {
  late final List<PatternVariableElement> variables;
  JumpTarget? entry;
}
