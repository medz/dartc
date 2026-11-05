import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'no_such_method.dart';
import 'assertion.dart';
import 'bindings.dart';
import 'expression.dart';
import 'function.dart';
import 'function_context.dart';
import 'global_declaration.dart';

/// Lowers a resolved class and appends its executable bodies to [functions].
IrClass lowerClass(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.ClassDeclaration declaration,
  List<IrFunction> functions,
) {
  return _lowerNominal(
    unit,
    bindings,
    declaration,
    declaration.declaredFragment!.element,
    declaration.namePart,
    declaration.body.members,
    functions,
  );
}

/// Lowers an enum using ordinary class storage and member bodies.
IrClass lowerEnum(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.EnumDeclaration declaration,
  List<IrFunction> functions,
) => _lowerNominal(
  unit,
  bindings,
  declaration,
  declaration.declaredFragment!.element,
  declaration.namePart,
  declaration.body.members,
  functions,
);

IrClass _lowerNominal(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.AstNode declaration,
  InterfaceElement element,
  ast.ClassNamePart namePart,
  List<ast.ClassMember> sourceMembers,
  List<IrFunction> functions,
) {
  final forwarders = bindings.forwarders(element);
  final type = bindings.classType(element, unit, declaration);
  final fields = <InstanceField>[];
  final members = <FunctionTarget>[];
  final constructors = <FunctionTarget>[];
  for (final field in element.fields) {
    if (field.isEnumConstant || field.isOriginEnumValues) {
      bindings.constantOf(field, unit, declaration);
      continue;
    }
    if (field.isStatic || field.isOriginGetterSetter) continue;
    if (field.isExternal) {
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
        final value = entry.emit(LoadField(slot!, receiver));
        entry.finish(value.type == .never ? Unreachable(value) : Return(value));
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
    // Enum instances exist only as constants. Their generative constructors
    // are checked by constant lowering and never have an executable entry.
    if (element is EnumElement && ctor.isGenerative) return;
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
          for (final member in sourceMembers.whereType<ast.FieldDeclaration>())
            if (!member.isStatic && !member.fields.isLate)
              for (final v in member.fields.variables) ?v.initializer,
        ...initializers,
      ],
      initialize: ctor.isFactory
          ? null
          : (context) => _initialize(
              context,
              declaration,
              sourceMembers,
              ctor,
              initializers,
            ),
    );
  }

  if (namePart case ast.PrimaryConstructorDeclaration primary) {
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
  for (final member in sourceMembers) {
    switch (member) {
      case ast.ConstructorDeclaration(:final body, :final initializers):
        constructor(
          member.declaredFragment!.element,
          member,
          body,
          initializers,
        );
      case ast.FieldDeclaration(isStatic: true, :final fields):
        for (final variable in fields.variables) {
          lowerGlobal(unit, bindings, variable, functions);
        }
      case ast.FieldDeclaration(fields: final fields) when fields.isLate:
        for (final variable in fields.variables) {
          if (variable.initializer case final expression?) {
            final field = variable.declaredFragment!.element as FieldElement;
            FunctionLowering.appendExpression(
              functions,
              unit,
              bindings,
              bindings.field(field, unit, variable).initializer!,
              expression,
            );
          }
        }
      case ast.FieldDeclaration() || ast.PrimaryConstructorBody():
        break;
      case ast.MethodDeclaration(:final body):
        final method = member.declaredFragment!.element;
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
  if (element is EnumElement &&
      !members.any(
        (member) => member.kind == .method && member.name == 'toString',
      )) {
    final target = FunctionTarget(
      type.library,
      'toString',
      ValueType.string,
      const [],
      owner: type,
      kind: .method,
    );
    final entry = Block(target.parameterTypes);
    final name = entry.emit(
      LoadField(CoreTypes.enumName, entry.parameters.first),
    );
    entry.finish(
      Return(entry.emit(StringConcat(Constant.string('${type.name}.'), name))),
    );
    members.add(target);
    functions.add(IrFunction(target, [entry]));
  }
  for (final forwarder in forwarders) {
    final bodyTarget = bindings.superWrapperTarget(forwarder);
    members.removeWhere((member) => member.selector == forwarder.selector);
    members.add(forwarder);
    functions.add(
      bodyTarget != null
          ? lowerSuperForwarder(bindings, forwarder, bodyTarget)
          : lowerNoSuchMethodForwarder(
              bindings,
              forwarder,
              bindings.noSuchMethodBodyTarget(
                element,
                forwarder,
                unit,
                declaration,
              ),
            ),
    );
  }
  return IrClass(
    type,
    fields,
    members: members,
    constructors: constructors,
    unsupportedForwarders: bindings.unsupportedForwarders(element),
  );
}

void _initialize(
  FunctionContext context,
  ast.AstNode declaration,
  List<ast.ClassMember> sourceMembers,
  ConstructorElement ctor,
  List<ast.ConstructorInitializer> initializers,
) {
  final bindings = context.bindings,
      unit = context.unit,
      receiver = context.receiver!;
  Value? evaluate(ast.Expression expression) =>
      lowerExpression(context, expression);
  void store(FieldElement field, Value value, ast.AstNode site) {
    final converted = context.normal(
      context.convert(value, context.typeOf(field.type, site)),
    );
    if (converted == null) return;
    context.emit(
      StoreField(bindings.field(field, unit, site), receiver, converted),
    );
  }

  void invoke(
    ConstructorElement target,
    ast.ArgumentList? arguments, {
    bool forwardSuper = false,
  }) {
    final init = bindings.target(target, unit, arguments ?? declaration);
    final args = context.arguments(
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
      context.emit(
        DirectCall(
          init,
          [receiver, ...bindings.bind(init, args)],
          ownerType: context.typeOf(
            target.returnType,
            arguments ?? declaration,
          ) as ClassType,
        ),
      );
    }
  }

  if (initializers case [
    ast.RedirectingConstructorInvocation(:final element, :final argumentList),
  ]) {
    invoke(element!, argumentList);
    return;
  }
  for (final member in sourceMembers.whereType<ast.FieldDeclaration>()) {
    if (member.isStatic || member.fields.isLate) continue;
    for (final variable in member.fields.variables) {
      if (variable.initializer case final expression?) {
        final value = evaluate(expression);
        if (value == null) return;
        store(
          variable.declaredFragment!.element as FieldElement,
          value,
          variable,
        );
        if (context.current == null) return;
      }
    }
  }
  for (final p
      in ctor.formalParameters.whereType<FieldFormalParameterElement>()) {
    store(p.field!, context.readLocal(p), declaration);
    if (context.current == null) return;
  }
  ast.ArgumentList? superArguments;
  for (final init in initializers) {
    switch (init) {
      case ast.ConstructorFieldInitializer(:final fieldName, :final expression):
        final value = evaluate(expression);
        if (value == null) return;
        store(fieldName.element! as FieldElement, value, init);
        if (context.current == null) return;
      case ast.AssertInitializer(:final condition, :final message):
        lowerAssert(context, condition, message);
        if (context.current == null) return;
      case ast.SuperConstructorInvocation(:final argumentList):
        superArguments = argumentList;
      default:
        unsupported(unit, init, 'constructor initializer');
    }
  }
  invoke(ctor.superConstructor!, superArguments, forwardSuper: true);
}
