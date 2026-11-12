import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'iteration.dart';
import 'intrinsic.dart';
import 'pattern.dart';

/// Converts a constant literal or evaluates mutable elements in source order.
Value? lowerCollection(
  FunctionContext context,
  ast.TypedLiteral literal,
  Value? Function(ast.Expression) evaluate,
) {
  if (literal.isConst) {
    return context.bindings.constantExpression(context.unit, literal);
  }
  final type = context.typeOf(literal.staticType!, literal) as ClassType;
  if (type.declaration == CoreTypes.list) {
    requireListSupport(
      context.unit.libraryElement,
      context.bindings.requireClass,
    );
  } else if (type.declaration == CoreTypes.map) {
    requireMapSupport(
      context.unit.libraryElement,
      context.bindings.requireClass,
    );
  } else if (type.declaration == CoreTypes.set) {
    context.bindings.requireClass(
      context.unit.libraryElement.typeProvider.setElement,
    );
  }
  final result = context.emit(NewCollection(type));
  final elements = switch (literal) {
    ast.ListLiteral(:final elements) => elements,
    ast.SetOrMapLiteral(:final elements) => elements,
  };
  void nonNull(Value value, void Function(Value) body) {
    final skip = JumpTarget(context);
    context.guard(context.testType(value, .nullType, negated: true), skip);
    if (context.current != null) body(context.refined(value));
    if (skip.hasIncoming) skip.enter();
  }

  void add(Value value) {
    final converted = context.normal(
      context.convert(value, type.typeArguments.single),
    );
    if (converted != null) context.emit(CollectionAdd(result, converted));
  }

  void element(ast.CollectionElement node) {
    if (context.current == null) return;
    switch (node) {
      case ast.Expression():
        final value = evaluate(node);
        if (value != null) add(value);
      case ast.NullAwareElement(:final value):
        final operand = evaluate(value);
        if (operand != null) nonNull(operand, add);
      case ast.MapLiteralEntry():
        final key = evaluate(node.key);
        if (key == null) return;
        void entry(Value key) {
          final convertedKey = context.normal(
            context.convert(key, type.typeArguments[0]),
          );
          if (convertedKey == null) return;
          key = convertedKey;
          final value = evaluate(node.value);
          if (value == null) return;
          void put(Value value) {
            final converted = context.normal(
              context.convert(value, type.typeArguments[1]),
            );
            if (converted != null) context.emit(MapPut(result, key, converted));
          }

          if (node.valueQuestion != null) {
            nonNull(value, put);
          } else {
            put(value);
          }
        }
        if (node.keyQuestion != null) {
          nonNull(key, entry);
        } else {
          entry(key);
        }
      case ast.SpreadElement():
        final source = evaluate(node.expression);
        if (source == null) return;
        void spread(Value value) {
          if (value.type is DynamicType) {
            final protocol = CoreTypes.view(type, CoreTypes.map) == null
                ? CoreTypes.iterableOf(.dynamicType)
                : CoreTypes.mapOf(.dynamicType, .dynamicType);
            final checked = context.normal(context.cast(value, protocol));
            if (checked == null) return;
            value = checked;
          }
          if (type.declaration == CoreTypes.map && type.accepts(value.type)) {
            context.emit(CollectionSpread(result, value, isMethodCall: true));
            return;
          }
          final iterable = type.declaration == CoreTypes.map
              ? context.emit(MapEntries(value))
              : value;
          final iterator = context.emit(GetIterator(iterable));
          final header = JumpTarget(context)
            ..jump()
            ..enter();
          final done = JumpTarget(context);
          context.guard(context.emit(IteratorMoveNext(iterator)), done);
          final current = context.emit(IteratorCurrent(iterator));
          if (type.declaration == CoreTypes.map) {
            final key = context.normal(
              context.convert(
                context.emit(LoadField(CoreTypes.mapEntryKey, current)),
                type.typeArguments[0],
              ),
            );
            if (key != null) {
              final entry = context.normal(
                context.convert(
                  context.emit(LoadField(CoreTypes.mapEntryValue, current)),
                  type.typeArguments[1],
                ),
              );
              if (entry != null) context.emit(MapPut(result, key, entry));
            }
          } else {
            add(current);
          }
          header.jump();
          done.enter();
        }
        if (node.isNullAware) {
          nonNull(source, spread);
        } else {
          spread(source);
        }
      case ast.IfElement():
        final subject = evaluate(node.expression);
        if (subject == null) return;
        final failed = JumpTarget(context), done = JumpTarget(context);
        context.inScope(() {
          final clause = node.caseClause;
          if (clause != null) {
            matchGuarded(
              context,
              clause.guardedPattern,
              subject,
              failed,
              evaluate,
            );
          } else {
            context.guard(subject, failed);
          }
          element(node.thenElement);
        });
        if (failed.hasIncoming) {
          done.jump();
          failed.enter();
          if (node.elseElement case final alternative?) element(alternative);
          done.enter();
        }
      case ast.ForElement():
        final exit = JumpTarget(context);
        if (node.forLoopParts case final ast.ForEachParts parts) {
          lowerForEach(
            context,
            parts,
            evaluate,
            () => element(node.body),
            exit,
          );
        } else {
          final parts = node.forLoopParts as ast.ForParts;
          lowerLoop(
            context,
            evaluate,
            () => element(node.body),
            parts.condition,
            exit,
            parts: parts,
          );
        }
        exit.enter();
      default:
        unsupported(context.unit, node, 'collection element');
    }
  }

  for (final node in elements) {
    element(node);
  }
  return context.current == null ? null : result;
}
