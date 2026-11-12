import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'assertion.dart';
import 'bindings.dart';
import 'expression.dart';
import 'function.dart';
import 'function_context.dart';
import 'global_declaration.dart';
import 'no_such_method.dart';

/// Lowers a nominal declaration, optionally at a concrete mixin application.
IrClass lowerClass(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.AstNode declaration,
  List<IrCallable> functions, {
  IrClass? application,
}) {
  final (element, namePart, _) = switch (declaration) {
    ast.ClassDeclaration(
      :final declaredFragment,
      :final namePart,
      :final body,
    ) =>
      (declaredFragment!.element, namePart, body.members),
    ast.EnumDeclaration(
      :final declaredFragment,
      :final namePart,
      :final body,
    ) =>
      (declaredFragment!.element, namePart, body.members),
    ast.MixinDeclaration(:final declaredFragment, :final body) => (
      declaredFragment!.element,
      null,
      body.members,
    ),
    ast.ClassTypeAlias(:final declaredFragment) => (
      declaredFragment!.element,
      null,
      const <ast.ClassMember>[],
    ),
    _ => unsupported(unit, declaration, 'nominal declaration'),
  };
  final sourceMembers = [
    for (final (sourceUnit, source) in bindings.fragmentsOf(element))
      for (final member in switch (source) {
        ast.ClassDeclaration(:final body) => body.members,
        ast.EnumDeclaration(:final body) => body.members,
        ast.MixinDeclaration(:final body) => body.members,
        _ => const <ast.ClassMember>[],
      })
        (sourceUnit, member),
  ];
  final interfaceOnly = application == null && element is MixinElement;
  final forwarders = application == null
      ? bindings.forwarders(element)
      : <FunctionTarget>[];
  final type =
      application?.type ?? bindings.classType(element, unit, declaration);
  final fieldInitializers = [
    for (final (sourceUnit, field) in sourceMembers)
      if (field is ast.FieldDeclaration &&
          !field.isStatic &&
          !field.fields.isLate)
        for (final variable in field.fields.variables)
          if (variable.initializer case final expression?)
            (sourceUnit, variable, expression),
  ];
  final expressions = fieldInitializers.map((field) => field.$3);
  FunctionTarget memberTarget(ExecutableElement member, ast.AstNode site) {
    final source = bindings.target(member, unit, site);
    return application == null || member.isStatic
        ? source
        : application.members[source.selector]!;
  }

  final fields = <InstanceField>[];
  final weakFields = <InstanceField>[];
  final ephemeronNames = <InstanceField, String>{};
  final members = <FunctionTarget>[];
  final implementations = <FunctionTarget>[];
  final constructors = <FunctionTarget>[...?application?.constructors.values];
  for (final field in element.fields) {
    if (field.isEnumConstant || field.isOriginEnumValues) {
      bindings.constantOf(field, unit, declaration);
      continue;
    }
    if (field.isStatic || field.isOriginGetterSetter) continue;
    final slot = field.isAbstract || field.isExternal || interfaceOnly
        ? null
        : bindings.field(field, unit, declaration, owner: type);
    if (slot != null) {
      fields.add(slot);
      if (slot.isLate && (slot.isFinal || slot.initializer == null)) {
        bindings.requireLateError(element.library, unit, declaration);
      }
    }
    for (final accessor in [field.getter, field.setter].nonNulls) {
      final target = memberTarget(accessor, declaration);
      members.add(target);
      if (target.isAbstract) continue;
      if (field.isExternal) {
        functions.add(IrExternal(target));
        continue;
      }
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
    ResolvedUnitResult unit,
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
    FunctionLowering.append(
      functions,
      unit,
      bindings,
      ctor,
      site,
      body,
      initializers: [
        if (ctor.isGenerative && ctor.redirectedConstructor == null)
          ...expressions,
        ...initializers,
      ],
      initialize: ctor.isFactory
          ? null
          : (context) => _initialize(
              context,
              declaration,
              fieldInitializers,
              ctor,
              initializers,
            ),
    );
  }

  if (application != null) {
    if (application.constructors['<mixin-fields>'] case final initializer?) {
      FunctionLowering.appendInitializer(
        functions,
        unit,
        bindings,
        initializer,
        declaration,
        expressions,
        (context) {
          _initializeFields(context, fieldInitializers);
          return null;
        },
      );
    }
  } else if (element is ClassElement && element.isMixinApplication) {
    for (final ctor in element.constructors) {
      constructor(unit, ctor, declaration, null, const []);
    }
  } else if (namePart case ast.PrimaryConstructorDeclaration primary) {
    constructor(
      unit,
      primary.declaredFragment!.element,
      primary,
      primary.body?.body,
      primary.body?.initializers ?? const [],
    );
  } else if (element.unnamedConstructor case final ctor?
      when ctor.isOriginImplicitDefault) {
    constructor(unit, ctor, declaration, null, const []);
  }
  for (final (unit, member) in sourceMembers) {
    final fragment = switch (member) {
      ast.ConstructorDeclaration(:final declaredFragment) => declaredFragment,
      ast.MethodDeclaration(:final declaredFragment) => declaredFragment,
      _ => null,
    };
    if (fragment != null && fragment != fragment.element.fragments.last) {
      continue;
    }
    // SDK static functions enter through their own dependency queue.
    if (element.library.isInSdk &&
        member is ast.MethodDeclaration &&
        member.isStatic) {
      continue;
    }
    final contracts = bindings.runtimeContracts;
    if (member is ast.FieldDeclaration &&
        contracts != null &&
        bindings.runtimeSources.contains(unit.uri)) {
      for (final annotation in member.metadata) {
        final value = bindings.constants.annotation(unit, annotation);
        if (value?.type case dart.InterfaceType(:final element)
            when element.library.uri == contracts) {
          for (final variable in member.fields.variables) {
            final field = bindings.field(
              variable.declaredFragment!.element as FieldElement,
              unit,
              variable,
              owner: type,
            );
            if (element == element.library.getClass('WeakSlot')) {
              weakFields.add(field);
            } else if (element == element.library.getClass('EphemeronKey')) {
              ephemeronNames[field] = value!
                  .getField('valueField')!
                  .toStringValue()!;
            }
          }
        }
      }
    }
    if (application != null &&
        (member is ast.ConstructorDeclaration ||
            member is ast.MethodDeclaration && member.isStatic ||
            member is ast.FieldDeclaration && member.isStatic)) {
      continue;
    }
    switch (member) {
      case ast.ConstructorDeclaration(:final body, :final initializers):
        constructor(
          unit,
          member.declaredFragment!.element,
          member,
          body,
          initializers,
        );
      case ast.FieldDeclaration(isStatic: true, :final fields):
        for (final variable in fields.variables) {
          lowerGlobal(unit, bindings, variable, functions);
        }
      case ast.FieldDeclaration(fields: final fields)
          when fields.isLate && !interfaceOnly:
        for (final variable in fields.variables) {
          if (variable.initializer case final expression?) {
            final field = variable.declaredFragment!.element as FieldElement;
            FunctionLowering.appendExpression(
              functions,
              unit,
              bindings,
              bindings.field(field, unit, variable, owner: type).initializer!,
              expression,
            );
          }
        }
      case ast.FieldDeclaration() || ast.PrimaryConstructorBody():
        break;
      case ast.MethodDeclaration(:final body):
        final method = member.declaredFragment!.element;
        final target = memberTarget(method, member);
        if (target.kind.isVirtual) members.add(target);
        if (!target.isAbstract &&
            !functions.any((function) => function.target == target)) {
          FunctionLowering.append(
            functions,
            unit,
            bindings,
            method,
            member,
            body,
            destination: target,
          );
        }
    }
  }
  if (element is EnumElement &&
      !members.any(
        (member) => member.kind == .method && member.name == 'toString',
      ) &&
      bindings
              .superTarget(
                type,
                element.library.typeProvider.objectElement.getMethod(
                  'toString',
                )!,
                unit,
                declaration,
              )
              .owner ==
          ValueType.object) {
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
    final declaredMember = members
        .where((m) => m.selector == forwarder.selector)
        .firstOrNull;
    if (declaredMember != null &&
        declaredMember.signature != forwarder.signature) {
      implementations.add(forwarder);
    } else {
      members.removeWhere((member) => member.selector == forwarder.selector);
      members.add(forwarder);
    }
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
  var referencePayload = false;
  ({
    InstanceField length,
    InstanceField data,
    InstanceField mutability,
    FunctionTarget spread,
  })?
  listStorage;
  for (final (sourceUnit, source) in bindings.fragmentsOf(element)) {
    if (!bindings.runtimeSources.contains(sourceUnit.uri) ||
        source is! ast.AnnotatedNode) {
      continue;
    }
    for (final annotation in source.metadata) {
      final value = bindings.constants.annotation(sourceUnit, annotation);
      if (value?.type case dart.InterfaceType(element: final annotationType)
          when annotationType.library.uri == bindings.runtimeContracts) {
        if (annotationType ==
            annotationType.library.getClass('ReferencePayload')) {
          referencePayload = true;
        } else if (annotationType ==
            annotationType.library.getClass('ConstantListStorage')) {
          InstanceField field(String key) => fields.singleWhere(
            (field) => field.name == value!.getField(key)!.toStringValue(),
          );
          listStorage = (
            length: field('length'),
            data: field('data'),
            mutability: field('mutability'),
            spread: bindings.target(
              element.getMethod(value!.getField('spread')!.toStringValue()!)!,
              sourceUnit,
              annotation,
            ),
          );
        }
      }
    }
  }
  return IrClass(
    type,
    fields,
    members: members,
    implementations: implementations,
    constructors: constructors,
    weakFields: weakFields,
    referencePayload: referencePayload,
    listStorage: listStorage,
    ephemerons: {
      for (final MapEntry(:key, :value) in ephemeronNames.entries)
        key: fields.singleWhere((field) => field.name == value),
    },
    unsupportedForwarders: application == null
        ? bindings.unsupportedForwarders(element)
        : const {},
  );
}

void _initialize(
  FunctionContext context,
  ast.AstNode declaration,
  List<(ResolvedUnitResult, ast.VariableDeclaration, ast.Expression)>
  fieldInitializers,
  ConstructorElement ctor,
  List<ast.ConstructorInitializer> initializers,
) {
  final bindings = context.bindings,
      unit = context.unit,
      receiver = context.receiver!;
  Value? evaluate(ast.Expression expression) =>
      lowerExpression(context, expression);

  void invoke(
    ConstructorElement target,
    ast.ArgumentList? arguments, {
    bool forwardSuper = false,
  }) {
    final call = bindings.initializerCall(
      ctor,
      target,
      unit,
      arguments ?? declaration,
    );
    final init = call.target;
    final args = context.arguments(
      arguments,
      evaluate,
      forwarded: {
        if (ctor.isOriginMixinApplication)
          for (final (i, p) in ctor.formalParameters.indexed)
            target.formalParameters[i]: context.readLocal(p),
        if (forwardSuper)
          for (final p
              in ctor.formalParameters.whereType<SuperFormalParameterElement>())
            p.superConstructorParameter!: context.readLocal(p),
      },
    );
    if (args != null && init.owner != ValueType.object) {
      context.emit(
        DirectCall(init, [
          receiver,
          ...bindings.bind(init, args),
        ], ownerType: call.ownerType),
      );
    }
  }

  if (initializers case [
    ast.RedirectingConstructorInvocation(:final element, :final argumentList),
  ]) {
    invoke(element!, argumentList);
    return;
  }
  _initializeFields(context, fieldInitializers);
  if (context.current == null) return;
  for (final p
      in ctor.formalParameters.whereType<FieldFormalParameterElement>()) {
    _storeInitializedField(
      context,
      p.field!,
      context.readLocal(p),
      declaration,
    );
    if (context.current == null) return;
  }
  ast.ArgumentList? superArguments;
  for (final init in initializers) {
    switch (init) {
      case ast.ConstructorFieldInitializer(:final fieldName, :final expression):
        final value = evaluate(expression);
        if (value == null) return;
        _storeInitializedField(
          context,
          fieldName.element! as FieldElement,
          value,
          init,
        );
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
  if (ctor.superConstructor case final parent?) {
    invoke(parent, superArguments, forwardSuper: true);
  }
}

void _initializeFields(
  FunctionContext context,
  List<(ResolvedUnitResult, ast.VariableDeclaration, ast.Expression)> fields,
) {
  final original = context.unit;
  try {
    for (final (unit, variable, expression) in fields) {
      context.unit = unit;
      final value = lowerExpression(context, expression);
      if (value == null) return;
      _storeInitializedField(
        context,
        variable.declaredFragment!.element as FieldElement,
        value,
        variable,
      );
      if (context.current == null) return;
    }
  } finally {
    context.unit = original;
  }
}

void _storeInitializedField(
  FunctionContext context,
  FieldElement field,
  Value value,
  ast.AstNode site,
) {
  final converted = context.normal(
    context.convert(value, context.typeOf(field.type, site)),
  );
  if (converted == null) return;
  final receiver = context.receiver!;
  context.emit(
    StoreField(
      context.bindings.field(
        field,
        context.unit,
        site,
        owner: (receiver.type as ClassType).declaration,
      ),
      receiver,
      converted,
    ),
  );
}
