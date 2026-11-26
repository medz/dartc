import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'assigned.dart';
import 'captures.dart';
import 'coroutine.dart';
import 'levels.dart';
import 'types.dart';

extension Unsupported on SourceUnit {
  /// The failure to translate [node].
  CompileFailure unsupported(AstNode node, String what) =>
      CompileFailure([problem(node, 'Not supported yet: $what.')]);
}

/// A block entered from several places, which agree on some variables.
///
/// Its parameters are the results that those supply, then the variables.
final class Join._(
  final HirBlock _block,
  final int _resultCount,
  final List<Object> _variables,

  /// The values of variables where it was made, which those that are declared
  /// later do not have.
  final Map<Object, HirValue> _values,
);

/// A `late` variable, whose cell has a [value] if [isSet].
///
/// [getter] gives it one before, if it has an initializer.
final class LateLocal(
  final HirField value,
  final HirField isSet,
  final HirFunction? getter,
);

/// The local functions and `late` variables of one function and the closures
/// inside.
final class Locals() {
  final functions = <Element, HirFunction>{};
  final lates = <Element, LateLocal>{};
}

/// A variable that no source declares.
final class Temporary();

/// Builds the blocks of one function and tracks its variables' values.
final class FunctionBuilder(
  final SourceUnit unit,
  final HirFunction function,
  List<FormalParameterElement> parameters, {

  /// What the function is a member of, whose object it takes first.
  final Level? ownLevel,

  /// What `this` is of, in members of extensions and extension types.
  var DartType? thisType,

  /// Whether the function first takes its own closure.
  final bool isClosure = false,

  /// What the lists of type arguments that the function takes next are for.
  final List<Element> typeOwners = const [],

  /// What the function returns where nothing says what.
  var HirValue Function()? fallback,

  /// The type of what the function returns.
  final DartType? returnType,

  /// Which variables closures share.
  final Captures? captures,

  /// The class of the cells for values of a type.
  final HirClass Function(HirType type)? cellClass,

  /// What is known of those around.
  Locals? locals,
}) {
  final Locals locals = locals ?? Locals();
  final _entry = HirBlock(function.parameters);
  late HirBlock _block = _entry;
  final _types = <Object, HirType>{};

  /// The values of variables, or the cells holding them.
  final _values = <Object, HirValue>{};

  /// The same variable in all of the patterns that declare it.
  static Object _same(Object variable) =>
      variable is Element ? variableOf(variable) : variable;

  this {
    final hasReceiver = ownLevel != null || thisType != null;
    if (!isClosure && hasReceiver) _receiver = _entry.parameters.first;
    _level = ownLevel;
    final hasObject = isClosure || hasReceiver;
    var given = _entry.parameters.skip(hasObject ? 1 : 0);
    for (final owner in typeOwners) {
      bindTypes(owner, given.first);
      given = given.skip(1);
    }
    // Functions made without source have no names for what they are given.
    for (final (i, parameter) in parameters.indexed) {
      final value = given.elementAt(i);
      declare(parameter, value.type);
      assign(parameter, value);
    }
  }

  HirClass cells(HirType type) => cellClass!(type);

  /// The library of the source translated.
  LibraryElement get library => unit.ast.declaredFragment!.element;

  /// The values that the function is given.
  List<HirValue> get inputs => _entry.parameters;

  /// The object that `this` is, where there is one.
  HirValue? get receiver => _receiver;
  HirValue? _receiver;

  /// What `this` is an object of.
  Level? get level => _level;
  Level? _level;

  /// Lets [value] be the object that `this` is, where [level] is translated.
  void setReceiver(HirValue value, Level? level) {
    _receiver = value;
    _level = level;
  }

  /// Does [work] as part of [level].
  T at<T>(Level level, T Function() work) {
    final before = _level;
    _level = level;
    final result = work();
    _level = before;
    return result;
  }

  /// The lists of type arguments known here, by what they are for.
  final typeLists = <Element, HirValue>{};

  HirValue? typesOf(Element? owner) => typeLists[owner];

  void bindTypes(Element owner, HirValue list) => typeLists[owner] = list;

  /// The lists that tell the type parameters of function types, which belong to
  /// nothing, and their places there.
  final typePlaces = <TypeParameterElement, (HirValue, int)>{};

  void bindParameters(List<TypeParameterElement> parameters, HirValue list) {
    for (final (i, parameter) in parameters.indexed) {
      typePlaces[parameter] = (list, i);
    }
  }

  /// Where the function can be left, if it can.
  Coroutine? coroutine;

  /// Gives [function] the blocks that can run.
  ///
  /// If [how] tells how to leave it, returns the class of what is kept then.
  HirClass? finish([HirCoroutine? how]) {
    // Only values that may be null may be left out.
    end(switch (function.result) {
      _ when fallback != null => HirReturn(fallback!()),
      null => HirReturn(),
      .reference => HirReturn(add(HirNull())),
      _ => HirUnreachable(),
    });
    if (how != null) {
      final split = splitCoroutine(_entry, how, function.name);
      function.define(split.blocks);
      return split.frame;
    }
    function.define(
      reversePostorder(
        _entry,
        (block) => block.terminator!.edges.map((edge) => edge.target),
      ),
    );
    return null;
  }

  /// Where throws go, innermost last.
  final _handlers = <Join>[];

  /// The exceptions and traces of the `catch` clauses around here.
  final List<(HirValue, HirValue)> caught = [];

  /// Adds an instruction that cannot throw.
  T add<T extends HirInstruction>(T instruction) {
    if (instruction is HirCalling) throw StateError('$instruction may throw.');
    return _block.add(instruction);
  }

  /// Where in the source what is translated now is, if that is known.
  int? position;

  /// Does [work] at [offset] in the source.
  T atPosition<T>(int offset, T Function() work) {
    final before = position;
    position = offset;
    try {
      return work();
    } finally {
      position = before;
    }
  }

  /// The name that traces of the stack give the function.
  late String frameName = function.name;

  /// Adds [calling], returning its result, if any.
  HirValue? call(HirCalling calling) {
    if (position case final at?) {
      calling.place ??= HirPlace(frameName, unit.uri, unit.lineAt(at));
    }
    if (_handlers.isEmpty) {
      _block.add(calling);
      return calling.type == null ? null : calling;
    }
    final next = HirBlock([?calling.type]);
    _block.end(HirInvoke(calling, HirEdge(next), _edge(_handlers.last)));
    _block = next;
    return next.parameters.firstOrNull;
  }

  /// Creates an object of [class_].
  HirValue create(HirClass class_) => call(HirNew(class_))!;

  /// Throws [exception] with [trace].
  void raise(HirValue exception, HirValue trace) => _handlers.isEmpty
      ? end(HirThrow(exception, trace))
      : jumpWith(_handlers.last, [exception, trace]);

  /// A block where throws can go.
  Join handler() => Join._(
    HirBlock(const [.reference, .reference]),
    2,
    const [],
    Map.of(_values),
  );

  /// Does [body], where throws go to [handler], which receives the exception
  /// and its trace.
  void within(Join handler, void Function() body) {
    _handlers.add(handler);
    body();
    _handlers.removeLast();
  }

  /// What one of two parts gives, depending on [condition].
  HirValue choose(
    HirValue condition,
    HirType type,
    HirValue Function() ifTrue,
    HirValue Function() ifFalse,
  ) {
    final exit = Join._(HirBlock([type]), 1, const [], Map.of(_values));
    branch(condition, () => jump(exit, ifTrue()), () => jump(exit, ifFalse()));
    return enter(exit)!;
  }

  /// Does [work], which throws, unless [condition] holds.
  void unless(HirValue condition, void Function() work) {
    final exit = Join._(HirBlock(), 0, const [], Map.of(_values));
    branch(condition, () => jump(exit), () {
      work();
      end(HirUnreachable());
    });
    enter(exit);
  }

  /// Calls [thrower], which throws, if [failed] holds.
  void throwIf(
    HirValue failed,
    HirFunction thrower, [
    List<HirValue> arguments = const [],
  ]) => branch(failed, () {
    call(HirCall(thrower, arguments));
    end(HirUnreachable());
  }, () {});

  /// A value that is never used, where one is needed.
  HirValue placeholder(HirType type) => add(switch (type) {
    .integer => HirConst(0),
    .float => HirConst(0.0),
    .boolean => HirConst(false),
    .reference => HirNull(),
  });

  /// Ends the current block; what follows is translated but cannot run.
  void end(HirTerminator terminator) {
    _block.end(terminator);
    _block = HirBlock();
  }

  /// The variables in scope whose objects stay as long as these are.
  final _kept = <VariableElement>[];

  /// Tells those that are in scope here from ones declared later.
  int get scope => _kept.length;

  /// Has the objects of the variables that were declared since [scope] stay
  /// until here.
  void stay([int scope = 0]) {
    for (final variable in _kept.skip(scope)) {
      // What is bound can be a cell, which is kept without being read.
      final value = _bound.contains(variable)
          ? _values[_same(variable)]!
          : read(variable);
      add(HirMachine(.addressOf, [value]));
    }
    if (scope == 0 && _keepsReceiver) {
      add(HirMachine(.addressOf, [receiver!]));
    }
  }

  late final bool _keepsReceiver =
      receiver != null && isFinalizable(level?.element.thisType ?? thisType);

  /// Ends the scope of those.
  void leave(int scope) {
    stay(scope);
    _kept.length = scope;
  }

  /// Declares the variable [given], not yet assigned.
  void declare(Object given, HirType type) {
    if (given is VariableElement && isFinalizable(given.type)) _kept.add(given);
    final variable = _same(given);
    _types[variable] = type;
    _values.remove(variable);
    if (_isCell(variable)) _values[variable] = create(cells(type));
  }

  /// The variables of [_kept] that are bound, not declared.
  final _bound = <VariableElement>{};

  /// Declares [variable], of which [value] is the value or the cell.
  void bind(Object variable, HirValue value, HirType type) {
    if (variable is VariableElement && isFinalizable(variable.type)) {
      _kept.add(variable);
      _bound.add(variable);
    }
    _types[variable] = type;
    _values[variable] = value;
  }

  bool _isCell(Object variable) => captures?.isCell(_same(variable)) ?? false;

  HirType? typeOf(Object variable) => _types[_same(variable)];

  /// The type of the value of [variable] or of the cell holding it.
  HirType? rawTypeOf(Object variable) =>
      _isCell(variable) || locals.lates.containsKey(variable)
      ? .reference
      : typeOf(variable);

  /// The value of [variable] or the cell holding it.
  HirValue raw(Object variable) =>
      _values[_same(variable)] ?? placeholder(rawTypeOf(variable)!);

  /// Gives [variable] a cell of its own, with the same value.
  void renew(Element variable) {
    if (!_isCell(variable)) return;
    final value = read(variable);
    _values[variable] = create(cells(_types[variable]!));
    assign(variable, value);
  }

  /// The current value of [variable].
  ///
  /// An unassigned one can only be read by code that cannot run, or passed to
  /// a join after which it is assigned again before it is read.
  HirValue read(Object variable) {
    final value = raw(variable);
    return _isCell(variable)
        ? add(HirLoad(cells(typeOf(variable)!).fields.single, value))
        : value;
  }

  void assign(Object given, HirValue value) {
    final variable = _same(given);
    if (value.type != _types[variable]) {
      throw StateError('Assigned ${value.type} to $variable.');
    }
    if (_isCell(variable)) {
      final field = cells(_types[variable]!).fields.single;
      add(HirStore(field, raw(variable), value));
    } else {
      _values[variable] = value;
    }
  }

  /// A block whose predecessors may have run different parts of [construct].
  ///
  /// Every variable declared outside and assigned inside becomes a parameter.
  /// [result] is the type of a value that each predecessor also supplies.
  Join join(AstNode construct, [HirType? result]) =>
      joinAll(construct, [?result]);

  /// Like [join], with any number of [results], and with the variables [others]
  /// as if they were assigned.
  Join joinAll(
    AstNode construct,
    List<HirType> results, [
    List<Object> others = const [],
  ]) {
    final variables = {
      for (final variable in <Object>[
        ...assignedIn(construct),
      ].followedBy(others.map(_same)))
        if (_types.containsKey(variable)) variable,
    }.toList();
    final block = HirBlock([
      ...results,
      for (final variable in variables) rawTypeOf(variable)!,
    ]);
    return Join._(block, results.length, variables, Map.of(_values));
  }

  HirEdge _edge(Join join, [List<HirValue> results = const []]) =>
      HirEdge(join._block, [...results, ...join._variables.map(raw)]);

  void jump(Join join, [HirValue? result]) => jumpWith(join, [?result]);

  void jumpWith(Join join, List<HirValue> results) =>
      end(HirJump(_edge(join, results)));

  /// What the predecessors of [join] supply.
  List<HirValue> resultsOf(Join join) =>
      join._block.parameters.take(join._resultCount).toList();

  /// Continues at [join], returning the first value its predecessors supply.
  HirValue? enter(Join join) {
    _block = join._block;
    _values
      ..clear()
      ..addAll(join._values);
    for (final (i, variable) in join._variables.indexed) {
      _values[variable] = join._block.parameters[join._resultCount + i];
    }
    return resultsOf(join).firstOrNull;
  }

  /// Runs one of two continuations, both starting from the current values.
  void branch(
    HirValue condition,
    void Function() ifTrue,
    void Function() ifFalse,
  ) {
    final left = HirBlock(), right = HirBlock();
    end(HirBranch(condition, HirEdge(left), HirEdge(right)));
    final values = Map.of(_values);
    _block = left;
    ifTrue();
    _values
      ..clear()
      ..addAll(values);
    _block = right;
    ifFalse();
  }
}

/// Where traces of the stack tell that [node] is.
int positionOf(Expression node) => switch (node) {
  MethodInvocation(:final methodName) => methodName.offset,
  PropertyAccess(:final propertyName) => propertyName.offset,
  PrefixedIdentifier(:final identifier) => identifier.offset,
  BinaryExpression(:final operator) => operator.offset,
  _ => node.offset,
};
