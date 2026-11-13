import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' show DartType;
import 'package:dartc/ir.dart';

import '../analyzer_metadata.dart';
import 'bindings.dart';
import 'ffi.dart';
import 'core_member.dart';
import 'closures.dart';

/// The open control-flow graph and local bindings for one function.
final class FunctionContext(
  /// The source unit used for resolved identities and diagnostic locations.
  var ResolvedUnitResult unit,

  /// The call targets shared by all functions in this batch.
  final Bindings bindings,
  final bool Function(VariableElement) _isWritten,
  final ClosurePlan _closures,
  final FunctionTarget target, {
  final bool isAsynchronous = false,
  required final void Function(ast.AstNode, void Function(), void Function())
  withFinally,
}) {
  /// The blocks created so far, with the function entry first.
  final blocks = <Block>[];

  /// Original source positions for operations and terminating blocks.
  final sourceLocations = <Object, SourceLocation>{};
  SourceLocation? _sourceLocation;

  /// Gives emitted operations this node's position without replacing child sites.
  T withSource<T>(ast.AstNode? site, T Function() lower) {
    if (site == null) return lower();
    final previous = _sourceLocation;
    final source = site.root as ast.CompilationUnit;
    final location = source.lineInfo.getLocation(site.offset);
    _sourceLocation =
        bindings.sourceLocation?.call(source, site.offset) ??
        (
          uri: source.declaredFragment!.source.uri,
          line: location.lineNumber,
          column: location.columnNumber,
        );
    try {
      return lower();
    } finally {
      _sourceLocation = previous;
    }
  }

  void _locate(Object operation) {
    if (_sourceLocation case final location?) {
      sourceLocations[operation] = location;
    }
  }

  /// Seals the current block at the active source operation.
  void finish(Terminator terminator) {
    _locate(current!);
    current!.finish(terminator);
  }

  /// The instance being initialized or invoked, when the entry has a receiver.
  Value? receiver;

  /// Resolves [type] in the same declaration table as the rest of the program.
  ValueType typeOf(DartType type, ast.AstNode site) => bindings
      .valueType(type, unit, site)
      .substitute(bindings.typeEnvironment(target));

  /// Converts the analyzer's resolved explicit or inferred invocation arguments.
  List<ValueType> typeArguments(Iterable<DartType>? types, ast.AstNode site) =>
      [for (final type in types ?? const <DartType>[]) typeOf(type, site)];

  /// Checks a deferred namespace before evaluating a member's arguments.
  void checkDeferred(ast.AstNode? source) {
    if (bindings.deferredImport(source) case final deferred?) {
      emit(CheckLibraryLoaded(deferred.reference));
    }
  }

  /// Checks each argument immediately, before evaluating the following argument.
  EvaluatedArguments? arguments(
    ast.ArgumentList? arguments,
    Value? Function(ast.Expression) evaluate, {
    Map<FormalParameterElement, Value> forwarded = const {},
  }) => evaluateArguments(
    arguments,
    (expression, parameter) => switch (parameter?.enclosingElement) {
      final ExecutableElement member when isAsFunction(member) =>
        bindings.constantExpression(unit, expression),
      _ => evaluate(expression),
    },
    forwarded: forwarded,
    convert: (value, parameter, site) =>
        normal(convert(value, typeOf(parameter.type, site))),
  );

  /// Evaluates unresolved arguments without checking a guessed parameter type.
  EvaluatedArguments? dynamicArguments(
    ast.ArgumentList? arguments,
    Value? Function(ast.Expression) evaluate,
  ) => evaluateArguments(
    arguments,
    (expression, _) => evaluate(expression),
    convert: (value, parameter, site) => value,
  );

  /// Dispatches an unresolved selector in the source library's private namespace.
  Value? dynamicMember(
    Value receiver,
    FunctionKind kind,
    String name,
    List<Value> positional, [
    Map<String, Value> named = const {},
    List<ValueType> typeArguments = const [],
  ]) {
    final core = unit.libraryElement.typeProvider.objectElement.library;
    for (final name in ['Object', 'Null', 'Invocation', 'NoSuchMethodError']) {
      bindings.requireClass(core.getClass(name)!);
    }
    return normal(
      emit(
        DynamicDispatch(
          receiver,
          (
            kind: kind,
            name: name,
            privateScope: name.startsWith('_') ? unit.libraryElement.uri : null,
          ),
          positional,
          named,
          typeArguments,
        ),
      ),
    );
  }

  /// Applies a resolved function instantiation without erasing its signature.
  Value instantiateFunction(
    Value function,
    Iterable<DartType>? arguments,
    ast.AstNode site,
  ) {
    final types = typeArguments(arguments, site);
    return types.isEmpty
        ? function
        : emit(InstantiateFunction(function, types));
  }

  /// Resolves a selected extension using its source receiver, not an IR type.
  ExtensionApplication? extensionApplication(
    ExecutableElement? member,
    ast.AstNode site, {
    ast.Expression? receiver,
    DartType? receiverType,
    bool unqualified = false,
    bool nullAware = false,
  }) {
    if (member == null ||
        !isExtensionOwner(member.enclosingElement) ||
        coreEnumField(member) != null) {
      return null;
    }
    if (member.isStatic) {
      unsupported(unit, site, 'extension instance member');
    }
    final lexical = unqualified
        ? site
              .thisOrAncestorOfType<ast.ExtensionDeclaration>()
              ?.declaredFragment
              ?.element
        : null;
    final lexicalReceiver = unqualified
        ? switch (site.thisOrAncestorMatching(
            (n) =>
                n is ast.ClassDeclaration ||
                n is ast.EnumDeclaration ||
                n is ast.ExtensionTypeDeclaration,
          )) {
            ast.ClassDeclaration(:final declaredFragment) =>
              declaredFragment!.element.thisType,
            ast.EnumDeclaration(:final declaredFragment) =>
              declaredFragment!.element.thisType,
            ast.ExtensionTypeDeclaration(:final declaredFragment) =>
              declaredFragment!.element.thisType,
            _ => null,
          }
        : null;
    final executable = bindings.extensionExecutable(member, unit, site)!;
    final arguments = typeArguments(
      extensionTypeArguments(
        member,
        unit.libraryElement,
        receiverType: receiver?.staticType ?? receiverType ?? lexicalReceiver,
        override: receiver is ast.ExtensionOverride ? receiver : null,
        lexicalExtension: lexical,
        nullAware: nullAware,
      ),
      site,
    );
    final application = ExtensionApplication(
      executable,
      arguments,
      executable.receiverType!.substitute({
        for (final (i, parameter) in executable.extensionParameters.indexed)
          parameter: arguments[i],
      }),
    );
    // Analyzer 14.7 leaves raw extension parameters in some explicit operator
    // result types, including enclosing record/context metadata. Do not emit
    // types whose declaration parameters escape into the caller.
    if (receiver is ast.ExtensionOverride &&
        (site is ast.BinaryExpression || site is ast.PrefixExpression) &&
        site is ast.Expression &&
        site.staticType != null) {
      final used = typeOf(site.staticType!, site).freeTypeParameters;
      for (final (i, parameter)
          in application.executable.extensionParameters.indexed) {
        if (used.contains(parameter) &&
            application.typeArguments[i] != parameter) {
          unsupported(
            unit,
            site,
            'unsubstituted analyzer extension operator result',
          );
        }
      }
    }
    return application;
  }

  /// Checks an extension receiver before evaluating subsequent operands.
  Value? memberReceiver(Value value, ExtensionApplication? application) =>
      application == null
      ? value
      : normal(convert(value, application.receiverType));

  /// Captures an already-checked extension receiver in an ordinary closure.
  Value bindExtension(
    ExtensionApplication application,
    Value receiver,
    ast.AstNode site,
  ) => emit(
    MakeClosure(
      _closures.extensionTearOff(
        bindings,
        target,
        application,
        site,
        typeArguments(
          extensionTearOffDefaults(application.executable.declaration),
          site,
        ),
        nativeTypeCheck: isAsFunction(application.executable.declaration)
            ? bindings.target(
                application.executable.declaration.library.getTopLevelFunction(
                  '_checkAsFunctionType',
                )!,
                unit,
                site,
              )
            : null,
      ),
      [receiver],
    ),
  );

  /// Lowers a resolved extension call after checking its receiver and arguments.
  Value? callExtension(
    ExtensionApplication application,
    Value receiver,
    EvaluatedArguments args,
    List<ValueType> memberTypes,
    ast.AstNode site,
  ) {
    if (isAsFunction(application.executable.declaration)) {
      if (memberTypes case [final FunctionType signature]) {
        final isLeaf = args.named['isLeaf'];
        return emit(
          MakeClosure(
            _closures.nativeFunction(
              target,
              site,
              receiver.type,
              signature,
              isLeaf: isLeaf == null
                  ? false
                  : (isLeaf as ScalarConstant).value as bool,
            ),
            [receiver],
          ),
        );
      }
      unsupported(unit, site, 'asFunction Dart function type');
    }
    if (memberTypes.isEmpty) {
      final value = lowerFfi(
        application.executable.declaration,
        [receiver, ...args.positional],
        emit,
        result: application.executable.target.signature
            .instantiate(application.typeArguments)
            .result,
        bind: (member) => bindings.target(member, unit, site),
        arrayAccess: (array, store) {
          final accessor = _closures.nativeArrayAccess(
            target,
            site,
            array,
            bindings.target(
              application.executable.declaration.library.getTopLevelFunction(
                '_arrayStart',
              )!,
              unit,
              site,
            ),
            store: store,
          );
          return emit(
            MakeClosure(accessor, [if (accessor.captures.isNotEmpty) receiver]),
          );
        },
        named: args.named,
      );
      if (value != null) return normal(value);
    }
    final callee = application.executable.target;
    return normal(
      emit(
        DirectCall(
          callee,
          bindings.bind(callee, (
            positional: [receiver, ...args.positional],
            named: args.named,
          )),
          typeArguments: [...application.typeArguments, ...memberTypes],
        ),
      ),
    );
  }

  /// Calls a resolved getter, setter or operator with its evaluated operands.
  Value? callPositionalMember(
    ExecutableElement? member,
    Value receiver,
    List<Value> args,
    ast.AstNode site, {
    bool direct = false,
    ExtensionApplication? extension,
  }) {
    if (coreEnumField(member) case final field? when args.isEmpty) {
      return normal(emit(LoadField(field, receiver)));
    }
    if (member == null ||
        member.isStatic ||
        extension == null && !isClassLike(member.enclosingElement)) {
      unsupported(unit, site, 'instance member binding');
    }
    if (coreRuntimeType(member)) {
      return normal(emit(ObjectRuntimeType(receiver, direct: direct)));
    }
    final checked = memberReceiver(receiver, extension);
    if (checked == null) return null;
    receiver = checked;
    final signature = extension == null || args.isEmpty
        ? null
        : extension.executable.sourceSignature.substitute({
            for (final (i, parameter)
                in extension.executable.extensionParameters.indexed)
              parameter: extension.typeArguments[i],
          }) as FunctionType;
    final converted = <Value>[];
    for (final (i, value) in args.indexed) {
      final argument = normal(
        convert(
          value,
          signature?.parameters[i] ??
              typeOf(member.formalParameters[i].type, site),
        ),
      );
      if (argument == null) return null;
      converted.add(argument);
    }
    args = converted;
    if (extension != null) {
      return callExtension(
        extension,
        receiver,
        (positional: args, named: {}),
        [],
        site,
      );
    }
    if (lowerFfi(member, [receiver, ...args], emit) case final value?) {
      return normal(value);
    }
    final target = direct
        ? bindings.superTarget(this.receiver!.type, member, unit, site)
        : bindings.target(member, unit, site);
    if (member.library.isDartCore &&
        (!direct || target.library.toString() == 'dart:core') &&
        !coreRuntimeMember(member)) {
      final operation = lowerCoreMember(member, receiver, args, bindings);
      if (operation != null) return normal(emit(operation));
    }
    return normal(
      emit(
        direct
            ? DirectCall(
                target,
                [receiver, ...args],
                ownerType: (receiver.type.nonNullable as ClassType)
                    .asInstanceOf(target.owner!),
              )
            : InstanceCall(target, receiver, args),
      ),
    );
  }

  /// The SSA value of each in-scope variable on the current path.
  final _locals = <Element, Value>{};
  final _declared = <Element>[];

  /// Writable bindings and their declared types, in edge-argument order.
  final mutableLocals = <(VariableElement, ValueType)>[];

  /// The block receiving instructions, or `null` after a terminating transfer.
  Block? current;
  _Refinement? _facts;

  /// The innermost handler for exceptions leaving the current operation.
  JumpTarget? handler;

  /// The exception and original trace in scope for a Dart `rethrow`.
  (Value, Value)? caught;

  Jump? get _unwind =>
      handler?.edge([UnwindValue.exception, UnwindValue.stackTrace]);

  List<Value> _finalizables([Iterable<Element>? variables]) => [
    if (variables == null &&
        receiver != null &&
        FfiTypes.includesFinalizable(receiver!.type))
      receiver!,
    for (final variable in variables ?? _locals.keys)
      if (variable is VariableElement &&
          FfiTypes.includesFinalizable(typeOf(variable.type, unit.unit)))
        _locals[variable]!,
  ];

  /// Retains current bindings without reading uninitialized late storage.
  void retainFinalizables([Iterable<Element>? variables]) {
    if (current == null) return;
    for (final value in _finalizables(variables)) {
      current!.emit(KeepAlive(value));
    }
  }

  Jump? _retainingUnwind(List<Value> values) {
    if (values.isEmpty) return _unwind;
    final cleanup = addBlock([.object, .stackTrace]);
    for (final value in values) {
      cleanup.emit(KeepAlive(value));
    }
    cleanup.finish(
      Throw(
        cleanup.parameters[0],
        stackTrace: cleanup.parameters[1],
        onThrow: _unwind,
      ),
    );
    return Jump(cleanup, [UnwindValue.exception, UnwindValue.stackTrace]);
  }

  /// Emits [operation], capturing the local values at this site if it can throw.
  Value emit(Instruction operation) {
    _locate(operation);
    if (!operation.mayThrow) return current!.emit(operation);
    final retained = operation.type == .never
        ? _finalizables()
        : const <Value>[];
    if (handler == null && retained.isEmpty) return current!.emit(operation);
    final next = operation.type == .never ? null : addBlock([operation.type]);
    finish(
      Invoke(
        operation,
        onReturn: next == null ? null : Jump(next, [operation]),
        onThrow: _retainingUnwind(retained)!,
      ),
    );
    current = next;
    return next?.parameters.single ?? operation;
  }

  /// Suspends after evaluating an operand, preserving this site's error edge.
  Value? awaitValue(Value operand, ValueType type) {
    if (!isAsynchronous) throw StateError('Await outside an async body.');
    final result = AwaitResult(type);
    final next = type == .never ? null : addBlock([type]);
    finish(
      Await(
        operand,
        result,
        onResume: next == null ? null : Jump(next, [result]),
        onThrow: type == .never ? _retainingUnwind(_finalizables()) : _unwind,
      ),
    );
    current = next;
    return next?.parameters.single;
  }

  /// Throws to the active handler or caller, preserving [stackTrace] for a rethrow.
  void raise(Value exception, [Value? stackTrace]) {
    finish(
      Throw(
        exception,
        stackTrace: stackTrace,
        onThrow: _retainingUnwind(_finalizables()),
      ),
    );
    current = null;
  }

  /// Raises the Dart error on a reachable exhaustive-switch miss.
  void exhaustivenessFailure() {
    current?.finish(ExhaustivenessFailure(_unwind));
    current = null;
  }

  bool hasLocal(Element? element) => _locals.containsKey(element);

  /// Reads a lexical value at the current program point.
  Value readLocal(Element element) {
    final stored = _locals[element]!;
    return stored.type is CellType ? emit(ReadCell(stored)) : stored;
  }

  /// Writes the binding or its shared captured storage.
  void writeLocal(VariableElement variable, Value value) {
    final stored = _locals[variable]!;
    final converted = normal(convert(value, typeOf(variable.type, unit.unit)));
    if (converted == null) return;
    value = converted;
    retainFinalizables([variable]);
    if (stored.type is CellType) {
      emit(WriteCell(stored, value));
    } else {
      _locals[variable] = value;
    }
  }

  /// Binds a declaration in the current lexical scope.
  void declare(VariableElement variable, ValueType type, Value initial) {
    final converted = normal(convert(initial, type));
    if (converted == null) return;
    initial = converted;
    _declared.add(variable);
    if (_closures.boxed.contains(variable)) {
      _locals[variable] = emit(NewCell(CellType(type), initial));
    } else {
      _locals[variable] = initial;
      if (_isWritten(variable)) mutableLocals.add((variable, type));
    }
  }

  /// Reserves a local whose first write is checked by Dart definite assignment.
  ///
  /// Storage permits branches to perform the first write without fabricating a
  /// Dart value of a non-nullable type on paths where it is not initialized.
  void declareUninitialized(VariableElement variable, ValueType type) {
    _declared.add(variable);
    _locals[variable] = emit(NewCell(CellType(type), null));
  }

  /// Reserves late storage without evaluating or reading its lazy captures.
  void declareLate(ast.VariableDeclaration declaration, ValueType type) {
    bindings.requireLateError(unit.libraryElement, unit, declaration);
    final variable = declaration.declaredFragment!.element;
    final initializer = declaration.initializer == null
        ? null
        : _close(_closures.functions[variable]!);
    _declared.add(variable);
    _locals[variable] = emit(
      NewCell(
        CellType(type, isLate: true, isFinal: variable.isFinal),
        null,
        initializer: initializer,
      ),
    );
  }

  /// Binds the lexical function itself or a capture supplied by the caller.
  void bindCapture(Element? element, Value value) {
    if (element == null) {
      receiver = value;
    } else {
      _locals[element] = value;
      _declared.add(element);
    }
  }

  /// Instantiates a function using this activation's values and shared cells.
  Value close(ast.FunctionExpression syntax) =>
      _close(_closures.functions[syntax.declaredFragment!.element]!);

  Value _close(LocalClosure fn) => emit(
    MakeClosure(fn.target, [
      for (final key in fn.captures)
        key == null
            ? receiver!
            : _locals[key] ??
                  (throw StateError(
                    'Unbound capture ${key.name} in ${fn.target.library}::${fn.target.name}',
                  )),
    ]),
  );

  /// Identifies header cells that must move to a fresh binding on each for iteration.
  List<VariableElement> forInitializer(void Function() initialize) {
    final mark = _declared.length;
    initialize();
    final variables = <VariableElement>[];
    for (final variable in _declared.skip(mark).whereType<VariableElement>()) {
      if (!_closures.boxed.contains(variable)) continue;
      if (_locals[variable]!.type case final CellType type) {
        variables.add(variable);
        mutableLocals.add((variable, type));
      }
    }
    return variables;
  }

  /// Copies a for-header binding before running the update expressions.
  void nextIteration(VariableElement variable) {
    final cell = _locals[variable]!;
    _locals[variable] = emit(CopyCell(cell));
  }

  /// Removes declarations introduced by [lower] when its scope ends.
  void inScope(void Function() lower) {
    final mark = _declared.length, mutableMark = mutableLocals.length;
    lower();
    retainFinalizables(_declared.skip(mark));
    while (_declared.length > mark) {
      _locals.remove(_declared.removeLast());
    }
    mutableLocals.length = mutableMark;
  }

  /// Ends the current block when [value] has no normal continuation.
  Value? normal(Value? value) {
    if (value != null && value.type == .never) {
      current?.finish(Unreachable(value));
      current = null;
      return null;
    }
    return value;
  }

  /// Jumps to [failure] on a false [condition] and keeps the true path open.
  void guard(
    Value? condition,
    JumpTarget failure, [
    List<Value> onFailure = const [],
  ]) {
    if (condition == null) return;
    condition = convert(condition, .boolean);
    if (condition case ScalarConstant(value: final bool passes)) {
      if (!passes) failure.jump(onFailure);
    } else {
      final origin = current!, leave = failure.edge(onFailure);
      origin.finish(Branch(condition, enterArm(condition, true), leave));
    }
  }

  /// The narrower operand established on the current path, if any.
  Value refined(Value value) {
    for (var fact = _facts; fact != null; fact = fact.previous) {
      if (fact.operand == value) return refined(fact.narrowed);
    }
    return value;
  }

  /// Checks [value] once and retains the non-null result on this path.
  Value checkNotNull(Value value) {
    final known = refined(value);
    if (!known.type.mayBeNull) return known;
    final checked = emit(NullCheck(known));
    _facts = _Refinement(value, checked, _facts);
    return checked;
  }

  /// Inserts an implicit runtime check only when assignment needs one.
  /// A union-to-class upcast retains the selected nominal view for member
  /// signatures even when neither union arm alone supplies that common view.
  Value convert(Value value, ValueType type) {
    if (!type.accepts(value.type)) return cast(value, type);
    if (type is ClassType &&
        (value.type is FutureOrType ||
            value.type is TypeParameterType ||
            value.type is NonNullableTypeParameterType) &&
        CoreTypes.view(value.type, type.declaration) == null) {
      return cast(value, type);
    }
    return value;
  }

  /// Checks [value] against [type] if its current binding does not establish the type.
  Value cast(Value value, ValueType type) {
    if (type.accepts(value.type)) {
      return type == value.type ? value : emit(TypeView(value, type));
    }
    final known = refined(value);
    if (type.accepts(known.type)) {
      return type == known.type ? known : emit(TypeView(known, type));
    }
    final cast = emit(TypeCast(known, type));
    if (known.type.accepts(type)) _facts = _Refinement(known, cast, _facts);
    return cast;
  }

  /// Tests the runtime type of [value] after its effects have been evaluated.
  Value testType(Value value, ValueType type, {bool negated = false}) {
    final known = refined(value);
    if (type.accepts(known.type)) return Constant.boolean(!negated);
    if (type == .never ||
        (known.type == .nullType && !type.mayBeNull) ||
        (type == .nullType && !known.type.mayBeNull)) {
      return Constant.boolean(negated);
    }
    return emit(TypeTest(known, type, negated: negated));
  }

  /// Opens an arm of [condition] and binds the value established by a type test.
  Jump enterArm(Value condition, bool taken) {
    final proof = condition is TypeTest ? condition.refinement(taken) : null;
    final block = addBlock([if (proof is TestedValue) proof.type]);
    if (condition is TypeTest && proof != null && proof != condition.operand) {
      final known = proof is TestedValue ? block.parameters.single : proof;
      _facts = _Refinement(condition.operand, known, _facts);
    }
    current = block;
    return .new(block, [if (proof is TestedValue) proof]);
  }

  /// Appends an open block with parameters of [types] and returns it.
  Block addBlock([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    blocks.add(block);
    return block;
  }

  /// Captures the bindings that may differ when another path reaches this point.
  List<Value> saveLocals([int? count]) {
    final end = count ?? mutableLocals.length;
    return end == 0
        ? const []
        : [
            for (var i = 0; i < end; i++)
              _mergeLocal(mutableLocals[i].$1, mutableLocals[i].$2),
          ];
  }

  Value _mergeLocal(VariableElement variable, ValueType type) {
    final value = _locals[variable]!, narrowed = refined(value);
    // Null on one path does not establish assignability to an open type parameter.
    return type.accepts(narrowed.type) ? narrowed : value;
  }

  /// Restores [values] at the same lexical scope in which they were captured.
  void restoreLocals(List<Value> values, [int offset = 0]) {
    for (final (i, (variable, _)) in mutableLocals.indexed) {
      _locals[variable] = values[offset + i];
    }
  }

  /// Returns edges from the [saved] and active paths to a new current block.
  ///
  /// If both paths produce a [result], the first block parameter carries it.
  /// The remaining parameters carry only locals that differ across the paths.
  (Jump, Jump) join(List<Value> saved, [(ValueType, Value, Value)? result]) {
    final types = <ValueType>[if (result != null) result.$1];
    final first = <Value>[if (result != null) result.$2];
    final second = <Value>[if (result != null) result.$3];
    final changed = <VariableElement>[];
    for (final (i, (variable, type)) in mutableLocals.indexed) {
      final value = _mergeLocal(variable, type);
      if (saved[i] == value) continue;
      types.add(type);
      first.add(saved[i]);
      second.add(value);
      changed.add(variable);
    }
    final block = addBlock(types);
    var slot = result == null ? 0 : 1;
    for (final variable in changed) {
      _locals[variable] = block.parameters[slot++];
    }
    current = block;
    return (.new(block, first), .new(block, second));
  }

  /// Lowers alternatives from the same local state and joins paths that return normally.
  Value? branch(
    Value condition,
    Value? Function() ifTrue,
    Value? Function() ifFalse, [
    ValueType? resultType,
  ]) {
    condition = convert(condition, .boolean);
    if (condition case ScalarConstant(value: final bool taken)) {
      return taken ? ifTrue() : ifFalse();
    }
    final origin = current!, before = saveLocals(), facts = _facts;
    final yes = enterArm(condition, true);
    final left = ifTrue(), yesEnd = current;
    final yesFacts = _facts;
    final yesValues = yesEnd == null ? null : saveLocals();
    _facts = facts;
    restoreLocals(before);
    final no = enterArm(condition, false);
    final right = ifFalse(), noEnd = current;
    origin.finish(Branch(condition, yes, no));
    if (yesEnd == null) return right;
    if (noEnd == null) {
      current = yesEnd;
      _facts = yesFacts;
      restoreLocals(yesValues!);
      return left;
    }
    _facts = facts;
    final (fromYes, fromNo) = join(
      yesValues!,
      resultType == null ? null : (resultType, left!, right!),
    );
    yesEnd.finish(fromYes);
    noEnd.finish(fromNo);
    return resultType == null ? null : current!.parameters.first;
  }

  /// Evaluates [fallback] only when [left] is null.
  Value? ifNull(Value left, ValueType resultType, Value? Function() fallback) {
    final known = refined(left);
    if (known.type == .nullType) return fallback();
    if (!known.type.mayBeNull) return known;
    final test = current!.emit(TypeTest(known, .nullType));
    return shortCircuit(
      test,
      evaluateWhen: true,
      skipped: test.refinement(false) ?? known,
      resultType: resultType,
      right: fallback,
    );
  }

  /// Evaluates [right] only on the selected edge and forwards [skipped] on the other.
  Value shortCircuit(
    Value condition, {
    required bool evaluateWhen,
    required Value skipped,
    required ValueType resultType,
    required Value? Function() right,
  }) {
    final originalCondition = condition;
    condition = convert(condition, .boolean);
    if (identical(skipped, originalCondition)) skipped = condition;
    final entry = current!, before = saveLocals(), facts = _facts;
    final enter = enterArm(condition, evaluateWhen);
    final input = right();
    final result = input == null ? null : convert(input, resultType);
    _facts = facts;
    final Jump skip;
    if (result == null) {
      restoreLocals(before);
      current = addBlock([resultType]);
      skip = Jump(current!, [skipped]);
    } else {
      final end = current!;
      final edges = join(before, (resultType, skipped, result));
      skip = edges.$1;
      end.finish(edges.$2);
    }
    entry.finish(
      Branch(
        condition,
        evaluateWhen ? enter : skip,
        evaluateWhen ? skip : enter,
      ),
    );
    return skip.target.parameters.first;
  }
}

final class _Refinement(
  final Value operand,
  final Value narrowed,
  final _Refinement? previous,
);

/// A jump destination carrying only the mutable locals visible at its boundary.
final class JumpTarget._(
  final FunctionContext _context,
  final int _localCount,
  final _Refinement? _facts,
  final List<ValueType> _inputs,
) {
  new(FunctionContext context, [List<ValueType> inputs = const []])
    : this._(context, context.mutableLocals.length, context._facts, inputs);
  Block? _block;

  /// Creates a second destination dominated by the same facts and declarations.
  JumpTarget sibling(List<ValueType> inputs) =>
      ._(_context, _localCount, _facts, inputs);

  /// Whether a path has already jumped here.
  bool get hasIncoming => _block != null;

  /// Creates the destination on its first incoming edge.
  Jump edge([List<Value> inputs = const []]) {
    final values = _context.saveLocals(_localCount);
    return .new(
      _block ??= _context.addBlock([
        ..._inputs,
        for (var i = 0; i < _localCount; i++) _context.mutableLocals[i].$2,
      ]),
      inputs.isEmpty ? values : [...inputs, ...values],
    );
  }

  /// Transfers the open path, if any, to this target.
  void jump([List<Value> inputs = const []]) {
    _context.retainFinalizables();
    _context.current?.finish(edge(inputs));
    _context.current = null;
  }

  /// Merges incoming jumps with fallthrough in the target's lexical scope.
  Block? enter() {
    final block = _block;
    if (block == null) return null;
    _context.current?.finish(edge());
    _context.current = block;
    _context._facts = _facts;
    _context.restoreLocals(block.parameters, _inputs.length);
    return block;
  }
}
