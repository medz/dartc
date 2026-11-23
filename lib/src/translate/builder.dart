import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'assigned.dart';

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
  final List<VariableElement> _variables,
);

/// Builds the blocks of one function and tracks its variables' values.
final class FunctionBuilder(
  final SourceUnit unit,
  final HirFunction function,
  List<FormalParameterElement> parameters, {

  /// The class of the object that the function's first parameter is.
  final ClassElement? receiverClass,

  /// The type of what the function returns.
  final DartType? returnType,
}) {
  final _entry = HirBlock(function.parameters);
  late HirBlock _block = _entry;
  final _types = <VariableElement, HirType>{};
  final _values = <VariableElement, HirValue>{};

  this {
    final given = _entry.parameters.skip(receiverClass == null ? 0 : 1);
    // Functions made without source have no names for what they are given.
    for (final (i, parameter) in parameters.indexed) {
      final value = given.elementAt(i);
      declare(parameter, value.type);
      assign(parameter, value);
    }
  }

  /// The library of the source translated.
  LibraryElement get library => unit.ast.declaredFragment!.element;

  /// The values that the function is given.
  List<HirValue> get inputs => _entry.parameters;

  /// The object that `this` is, where there is one.
  HirValue? get receiver =>
      receiverClass == null ? null : _entry.parameters.first;

  /// Gives [function] the blocks that can run.
  void finish() {
    // Only values that may be null may be left out.
    end(switch (function.result) {
      null => HirReturn(),
      .reference => HirReturn(add(HirNull())),
      _ => HirUnreachable(),
    });
    function.define(
      reversePostorder(
        _entry,
        (block) => block.terminator!.edges.map((edge) => edge.target),
      ),
    );
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

  /// Adds [calling], returning its result, if any.
  HirValue? call(HirCalling calling) {
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
    final exit = Join._(HirBlock([type]), 1, const []);
    branch(condition, () => jump(exit, ifTrue()), () => jump(exit, ifFalse()));
    return enter(exit)!;
  }

  /// Does [work], which throws, unless [condition] holds.
  void unless(HirValue condition, void Function() work) {
    final exit = Join._(HirBlock(), 0, const []);
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

  /// Declares [variable], not yet assigned.
  void declare(VariableElement variable, HirType type) =>
      _types[variable] = type;

  HirType? typeOf(VariableElement variable) => _types[variable];

  /// The current value of [variable].
  ///
  /// An unassigned one can only be read by code that cannot run, or passed to
  /// a join after which it is assigned again before it is read.
  HirValue read(VariableElement variable) =>
      _values[variable] ?? placeholder(_types[variable]!);

  void assign(VariableElement variable, HirValue value) {
    if (value.type != _types[variable]) {
      throw StateError('Assigned ${value.type} to ${variable.name}.');
    }
    _values[variable] = value;
  }

  /// A block whose predecessors may have run different parts of [construct].
  ///
  /// Every variable declared outside and assigned inside becomes a parameter.
  /// [result] is the type of a value that each predecessor also supplies.
  Join join(AstNode construct, [HirType? result]) =>
      joinAll(construct, [?result]);

  /// Like [join], with any number of [results].
  Join joinAll(AstNode construct, List<HirType> results) {
    final variables = [
      for (final variable in assignedIn(construct))
        if (_types.containsKey(variable)) variable,
    ];
    final block = HirBlock([
      ...results,
      for (final variable in variables) _types[variable]!,
    ]);
    return Join._(block, results.length, variables);
  }

  HirEdge _edge(Join join, [List<HirValue> results = const []]) =>
      HirEdge(join._block, [...results, ...join._variables.map(read)]);

  void jump(Join join, [HirValue? result]) => jumpWith(join, [?result]);

  void jumpWith(Join join, List<HirValue> results) =>
      end(HirJump(_edge(join, results)));

  /// What the predecessors of [join] supply.
  List<HirValue> resultsOf(Join join) =>
      join._block.parameters.take(join._resultCount).toList();

  /// Continues at [join], returning the first value its predecessors supply.
  HirValue? enter(Join join) {
    _block = join._block;
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
