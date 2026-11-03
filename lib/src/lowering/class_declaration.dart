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
  final members = <FunctionTarget>[];
  final constructors = <FunctionTarget>[];
  for (final field in element.fields) {
    if (field.isOriginGetterSetter) continue;
    if (field.isStatic || field.isLate || field.isExternal) {
      unsupported(unit, declaration, 'field ${field.displayName}');
    }
    final slot = field.isAbstract
        ? null
        : bindings.field(field, unit, declaration);
    if (slot != null) fields.add(slot);
    for (final accessor in [field.getter, field.setter].nonNulls) {
      final target = bindings.target(accessor, unit, declaration);
      members.add(target);
      if (target.isAbstract) continue;
      final entry = Block(target.parameterTypes);
      final receiver = entry.parameters.first;
      if (accessor is GetterElement) {
        entry.finish(Return(entry.emit(LoadField(slot!, receiver))));
      } else {
        entry.emit(StoreField(slot!, receiver, entry.parameters[1]));
        entry.finish(const Return());
      }
      functions.add(IrFunction(target, [entry]));
    }
  }

  void constructor(
    ConstructorElement ctor,
    ast.AstNode site,
    ast.FunctionBody? body,
    List<ast.ConstructorInitializer> initializers,
  ) {
    final target = bindings.target(ctor, unit, site);
    constructors.add(target);
    if (target.redirect != null) return;
    if (ctor.isExternal) unsupported(unit, site, 'external constructor');
    FunctionLowering.append(
      functions,
      unit,
      bindings,
      ctor,
      site,
      body,
      initializers: [
        if (ctor.isGenerative && ctor.redirectedConstructor == null)
          for (final member
              in declaration.body.members.whereType<ast.FieldDeclaration>())
            if (!member.isStatic)
              for (final v in member.fields.variables) ?v.initializer,
        ...initializers,
      ],
      initialize: ctor.isFactory
          ? null
          : (context) => _initialize(context, declaration, ctor, initializers),
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
      case ast.MethodDeclaration(:final body):
        final method = member.declaredFragment!.element;
        if (method.isStatic && method is PropertyAccessorElement) {
          unsupported(unit, member, 'static accessor');
        }
        final target = bindings.target(method, unit, member);
        if (target.kind.isVirtual) members.add(target);
        if (!target.isAbstract) {
          FunctionLowering.append(
            functions,
            unit,
            bindings,
            method,
            member,
            body,
          );
        }
    }
  }
  return IrClass(type, fields, members: members, constructors: constructors);
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
    final args = evaluateArguments(
      arguments,
      evaluate,
      forwarded: {
        if (forwardSuper)
          for (final p
              in ctor.formalParameters.whereType<SuperFormalParameterElement>())
            p.superConstructorParameter!: context.readLocal(p),
      },
    );
    if (args != null && !target.enclosingElement.thisType.isDartCoreObject) {
      context.emit(DirectCall(init, [receiver, ...bindings.bind(init, args)]));
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
    store(p.field!, context.readLocal(p), declaration);
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
