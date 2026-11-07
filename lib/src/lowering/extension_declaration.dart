import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'assertion.dart';
import 'bindings.dart';
import 'expression.dart';
import 'function.dart';
import 'global_declaration.dart';

/// Emits extension bodies as static targets with explicit receiver parameters.
void lowerExtension(
  ResolvedUnitResult unit,
  Bindings bindings,
  Iterable<ast.ClassMember> members,
  List<IrCallable> functions,
) {
  for (final member in members) {
    switch (member) {
      case ast.MethodDeclaration(:final body):
        FunctionLowering.append(
          functions,
          unit,
          bindings,
          member.declaredFragment!.element,
          member,
          body,
        );
      case ast.FieldDeclaration(isStatic: true, :final fields):
        for (final variable in fields.variables) {
          lowerGlobal(unit, bindings, variable, functions);
        }
      default:
        unsupported(unit, member, 'extension member declaration');
    }
  }
}

/// Constructors return the representation; members use the static receiver ABI.
void lowerExtensionType(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.ExtensionTypeDeclaration declaration,
  List<IrCallable> functions,
) {
  final element = declaration.declaredFragment!.element;
  final getter = bindings.target(
    element.representation.getter!,
    unit,
    declaration,
  );
  final entry = Block(getter.parameterTypes);
  final value = entry.parameters.single;
  entry.finish(value.type == .never ? Unreachable(value) : Return(value));
  functions.add(IrFunction(getter, [entry]));

  void constructor(
    ConstructorElement ctor,
    ast.AstNode site,
    ast.FunctionBody? body,
    List<ast.ConstructorInitializer> initializers,
  ) {
    FunctionLowering.append(
      functions,
      unit,
      bindings,
      ctor,
      site,
      body,
      initializers: initializers,
      initialize: ctor.isFactory
          ? null
          : (context) {
              void representation(Value value) {
                context.receiver = context.normal(
                  context.convert(
                    value,
                    context.typeOf(element.representation.type, site),
                  ),
                );
              }

              for (final p
                  in ctor.formalParameters
                      .whereType<FieldFormalParameterElement>()) {
                representation(context.readLocal(p));
                if (context.current == null) return;
              }
              // Erased construction evaluates its representation before assertions,
              // even when an assertion precedes the field initializer in source.
              for (final init in [
                ...initializers.where((i) => i is! ast.AssertInitializer),
                ...initializers.whereType<ast.AssertInitializer>(),
              ]) {
                switch (init) {
                  case ast.ConstructorFieldInitializer(:final expression):
                    final value = lowerExpression(context, expression);
                    if (value == null) return;
                    representation(value);
                  case ast.AssertInitializer(:final condition, :final message):
                    lowerAssert(context, condition, message);
                  case ast.RedirectingConstructorInvocation(
                    :final element,
                    :final argumentList,
                  ):
                    final target = bindings.target(element!, unit, init);
                    final args = context.arguments(
                      argumentList,
                      (e) => lowerExpression(context, e),
                    );
                    if (args == null) return;
                    representation(
                      context.emit(
                        DirectCall(
                          target,
                          bindings.bind(target, args),
                          typeArguments: context.typeArguments(
                            element.returnType.typeArguments,
                            init,
                          ),
                        ),
                      ),
                    );
                  default:
                    unsupported(
                      unit,
                      init,
                      'extension type constructor initializer',
                    );
                }
                if (context.current == null) return;
              }
            },
    );
  }

  final primary = declaration.namePart as ast.PrimaryConstructorDeclaration;
  constructor(
    element.primaryConstructor,
    primary,
    primary.body?.body,
    primary.body?.initializers ?? const [],
  );
  for (final member
      in declaration.body.members.whereType<ast.ConstructorDeclaration>()) {
    constructor(
      member.declaredFragment!.element,
      member,
      member.body,
      member.initializers,
    );
  }
  lowerExtension(
    unit,
    bindings,
    declaration.body.members.where(
      (m) =>
          m is! ast.ConstructorDeclaration && m is! ast.PrimaryConstructorBody,
    ),
    functions,
  );
}
