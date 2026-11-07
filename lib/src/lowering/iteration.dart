import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'local_declaration.dart';
import 'pattern.dart';

/// Shares loop backedges and update targets without owning statement jumps.
void lowerLoop(
  FunctionContext context,
  Value? Function(ast.Expression) evaluate,
  void Function() body,
  ast.Expression? condition,
  JumpTarget exit, {
  void Function(void Function())? setContinue,
  bool testAfterBody = false,
  ast.ForParts? parts,
}) {
  context.inScope(() {
    final iteration = parts == null
        ? const <VariableElement>[]
        : context.forInitializer(() {
            switch (parts) {
              case ast.ForPartsWithDeclarations(:final variables):
                lowerVariables(context, variables, evaluate);
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
    final updates = parts?.updaters ?? const <ast.Expression>[];
    final header = JumpTarget(context)
      ..jump()
      ..enter();
    final next = testAfterBody || updates.isNotEmpty || iteration.isNotEmpty
        ? JumpTarget(context)
        : header;
    setContinue?.call(next.jump);
    if (!testAfterBody && condition != null) {
      context.guard(evaluate(condition), exit);
    }
    if (context.current != null) {
      body();
      if (next != header) next.enter();
      if (context.current != null) {
        for (final variable in iteration) {
          context.nextIteration(variable);
        }
        for (final update in updates) {
          if (evaluate(update) == null) break;
        }
        if (testAfterBody) {
          context.guard(evaluate(condition!), exit);
        }
        header.jump();
      }
    }
  });
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
  var iterable = evaluate(parts.iterable);
  if (iterable == null) return;
  final asynchronous = switch (parts.parent) {
    ast.ForStatement(:final awaitKeyword) ||
    ast.ForElement(:final awaitKeyword) => awaitKeyword != null,
  };
  if (iterable.type is DynamicType) {
    iterable = context.normal(
      context.cast(
        iterable,
        asynchronous
            ? CoreTypes.streamOf(.dynamicType)
            : CoreTypes.iterableOf(.dynamicType),
      ),
    );
    if (iterable == null) return;
  }
  FunctionTarget? moveNext, current, cancel;
  late final Value iterator;
  if (asynchronous) {
    final element = context
        .unit
        .libraryElement
        .typeProvider
        .streamElement
        .library
        .getClass('StreamIterator')!;
    final bindings = context.bindings, unit = context.unit;
    final type = bindings.classType(element, unit, parts).instantiate([
      CoreTypes.view(iterable.type, CoreTypes.stream)!.typeArguments.single,
    ]);
    iterator = context.emit(
      DirectCall(bindings.target(element.unnamedConstructor!, unit, parts), [
        iterable,
      ], ownerType: type),
    );
    moveNext = bindings.target(element.getMethod('moveNext')!, unit, parts);
    current = bindings.target(element.getGetter('current')!, unit, parts);
    cancel = bindings.target(element.getMethod('cancel')!, unit, parts);
  } else {
    iterator = context.emit(GetIterator(iterable));
  }
  void loop() {
    final header = JumpTarget(context)
      ..jump()
      ..enter();
    final done = asynchronous ? JumpTarget(context) : exit;
    setContinue?.call(header.jump);
    final next = moveNext == null
        ? context.emit(IteratorMoveNext(iterator))
        : context.awaitValue(
            context.emit(InstanceCall(moveNext, iterator, [])),
            .boolean,
          );
    context.guard(next, done);
    context.inScope(() {
      final value = context.emit(
        current == null
            ? IteratorCurrent(iterator)
            : InstanceCall(current, iterator, []),
      );
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
    if (asynchronous) done.enter();
  }

  if (cancel != null) {
    context.withFinally(parts.parent, loop, () {
      context.awaitValue(
        context.emit(InstanceCall(cancel!, iterator, [])),
        .dynamicType,
      );
    });
  } else {
    loop();
  }
}
