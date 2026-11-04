import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'pattern.dart';

/// Evaluates a collection literal in source order using mutable core storage.
Value? lowerCollection(
  FunctionContext context,
  ast.TypedLiteral literal,
  Value? Function(ast.Expression) evaluate,
) {
  if (literal.isConst) {
    unsupported(context.unit, literal, 'constant collection');
  }
  final type = context.typeOf(literal.staticType!, literal) as ClassType;
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

  void element(ast.CollectionElement node) {
    if (context.current == null) return;
    switch (node) {
      case ast.Expression():
        final value = evaluate(node);
        if (value != null) context.emit(CollectionAdd(result, value));
      case ast.NullAwareElement(:final value):
        final operand = evaluate(value);
        if (operand != null) {
          nonNull(operand, (v) => context.emit(CollectionAdd(result, v)));
        }
      case ast.MapLiteralEntry():
        final key = evaluate(node.key);
        if (key == null) return;
        void entry(Value key) {
          final value = evaluate(node.value);
          if (value == null) return;
          void put(Value value) {
            context.emit(MapPut(result, key, value));
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
          context.emit(CollectionSpread(result, value));
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
        if (node.awaitKeyword != null) {
          unsupported(context.unit, node, 'asynchronous collection for');
        }
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
          context.inScope(() {
            final iteration = context.forInitializer(() {
              switch (parts) {
                case ast.ForPartsWithDeclarations(:final variables):
                  for (final declaration in variables.variables) {
                    if (declaration.isLate) {
                      unsupported(
                        context.unit,
                        declaration,
                        'late collection loop variable',
                      );
                    }
                    final local = declaration.declaredFragment!.element;
                    final type = context.typeOf(local.type, declaration);
                    final initializer = declaration.initializer;
                    if (initializer == null && !type.accepts(.nullType)) {
                      context.declareUninitialized(local, type);
                    } else {
                      final value = initializer == null
                          ? const Constant.nullValue()
                          : evaluate(initializer);
                      if (value == null) return;
                      context.declare(local, type, value);
                    }
                  }
                case ast.ForPartsWithExpression(:final initialization):
                  if (initialization != null) evaluate(initialization);
                case ast.ForPartsWithPattern(:final variables):
                  declarePattern(
                    context,
                    variables.pattern,
                    evaluate(variables.expression),
                  );
              }
            });
            if (context.current == null) return;
            final header = JumpTarget(context)
              ..jump()
              ..enter();
            if (parts.condition case final condition?) {
              context.guard(evaluate(condition), exit);
            }
            element(node.body);
            if (context.current != null) {
              for (final local in iteration) {
                context.nextIteration(local);
              }
              for (final update in parts.updaters) {
                if (evaluate(update) == null) break;
              }
              header.jump();
            }
          });
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

/// Lowers the iterator protocol with a fresh declaration scope per iteration.
void lowerForEach(
  FunctionContext context,
  ast.ForEachParts parts,
  Value? Function(ast.Expression) evaluate,
  void Function() body,
  JumpTarget exit, {
  void Function(void Function())? setContinue,
}) {
  final iterable = evaluate(parts.iterable);
  if (iterable == null) return;
  final iterator = context.emit(GetIterator(iterable));
  final header = JumpTarget(context)
    ..jump()
    ..enter();
  setContinue?.call(header.jump);
  context.guard(context.emit(IteratorMoveNext(iterator)), exit);
  context.inScope(() {
    final value = context.emit(IteratorCurrent(iterator));
    switch (parts) {
      case ast.ForEachPartsWithDeclaration(:final loopVariable):
        final local = loopVariable.declaredFragment!.element;
        final type = context.typeOf(local.type, loopVariable);
        context.declare(local, type, context.cast(value, type));
      case ast.ForEachPartsWithIdentifier(:final identifier):
        final local = identifier.element;
        if (local is! VariableElement || !context.hasLocal(local)) {
          unsupported(context.unit, identifier, 'for-in assignment target');
        }
        context.writeLocal(
          local,
          context.cast(value, context.typeOf(local.type, identifier)),
        );
      case ast.ForEachPartsWithPattern(:final pattern):
        declarePattern(context, pattern, value);
    }
    if (context.current != null) body();
  });
  header.jump();
}
