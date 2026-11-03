import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'expression.dart';
import 'function.dart';
import 'function_context.dart';

/// Lowers a resolved class and appends its executable bodies to [functions].
IrClass lowerClass(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.ClassDeclaration declaration,
  List<IrFunction> functions,
) {
  final element = declaration.declaredFragment!.element;
  final type = bindings.classType(element, unit, declaration);
  final fields = <InstanceField>[];
  for (final field in element.fields) {
    if (field.isOriginGetterSetter) continue;
    if (field.isStatic ||
        field.isLate ||
        field.isAbstract ||
        field.isExternal) {
      unsupported(unit, declaration, 'field ${field.displayName}');
    }
    fields.add(bindings.field(field, unit, declaration));
  }

  void constructor(
    ConstructorElement ctor,
    ast.AstNode site,
    ast.FunctionBody? body,
    List<ast.ConstructorInitializer> initializers,
  ) {
    if (ctor.isExternal ||
        ctor.isFactory && ctor.redirectedConstructor != null) {
      unsupported(unit, site, 'external or redirecting factory constructor');
    }
    final lowering = FunctionLowering(unit, bindings, ctor, site, body);
    functions.add(
      lowering.run(
        ctor.isFactory
            ? null
            : (context) =>
                  _initialize(context, declaration, ctor, initializers),
      ),
    );
  }

  if (declaration.namePart case ast.PrimaryConstructorDeclaration primary) {
    constructor(
      primary.declaredFragment!.element,
      primary,
      primary.body?.body,
      primary.body?.initializers ?? const [],
    );
  } else if (element.unnamedConstructor case final ctor?
      when ctor.isOriginImplicitDefault) {
    constructor(ctor, declaration, null, const []);
  }
  for (final member in declaration.body.members) {
    switch (member) {
      case ast.ConstructorDeclaration(:final body, :final initializers):
        constructor(
          member.declaredFragment!.element,
          member,
          body,
          initializers,
        );
      case ast.FieldDeclaration() || ast.PrimaryConstructorBody():
        break;
      case ast.MethodDeclaration(
        isStatic: true,
        isGetter: false,
        isSetter: false,
        :final body,
      ):
        functions.add(
          FunctionLowering(
            unit,
            bindings,
            member.declaredFragment!.element,
            member,
            body,
          ).run(),
        );
      default:
        unsupported(unit, member, 'class member');
    }
  }
  return IrClass(type, fields);
}

void _initialize(
  FunctionContext context,
  ast.ClassDeclaration declaration,
  ConstructorElement ctor,
  List<ast.ConstructorInitializer> initializers,
) {
  final bindings = context.bindings,
      unit = context.unit,
      receiver = context.receiver!;
  Value? evaluate(ast.Expression expression) =>
      lowerExpression(context, expression);
  void store(FieldElement field, Value value, ast.AstNode site) {
    context.emit(
      StoreField(bindings.field(field, unit, site), receiver, value),
    );
  }

  void invoke(
    ConstructorElement target,
    ast.ArgumentList? arguments, {
    bool forwardSuper = false,
  }) {
    final init = bindings.target(target, unit, arguments ?? declaration);
    final args = bindings.arguments(
      target,
      arguments,
      unit,
      evaluate,
      forwarded: {
        if (forwardSuper)
          for (final p
              in ctor.formalParameters.whereType<SuperFormalParameterElement>())
            p.superConstructorParameter!: context.locals[p]!,
      },
    );
    if (args != null && !target.enclosingElement.thisType.isDartCoreObject) {
      context.emit(DirectCall(init, [receiver, ...args]));
    }
  }

  if (initializers case [
    ast.RedirectingConstructorInvocation(:final element, :final argumentList),
  ]) {
    invoke(element!, argumentList);
    return;
  }
  for (final member
      in declaration.body.members.whereType<ast.FieldDeclaration>()) {
    if (member.isStatic) continue;
    for (final variable in member.fields.variables) {
      if (variable.initializer case final expression?) {
        final value = evaluate(expression);
        if (value == null) return;
        store(
          variable.declaredFragment!.element as FieldElement,
          value,
          variable,
        );
      }
    }
  }
  for (final p
      in ctor.formalParameters.whereType<FieldFormalParameterElement>()) {
    store(p.field!, context.locals[p]!, declaration);
  }
  ast.ArgumentList? superArguments;
  for (final init in initializers) {
    switch (init) {
      case ast.ConstructorFieldInitializer(:final fieldName, :final expression):
        final value = evaluate(expression);
        if (value == null) return;
        store(fieldName.element! as FieldElement, value, init);
      case ast.SuperConstructorInvocation(:final argumentList):
        superArguments = argumentList;
      default:
        unsupported(unit, init, 'constructor initializer');
    }
  }
  invoke(ctor.superConstructor!, superArguments, forwardSuper: true);
}
