import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
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
final class Join._(
  final HirBlock _block,
  final List<VariableElement> _variables,
);

/// Builds the blocks of one function and tracks its variables' values.
final class FunctionBuilder(
  final SourceUnit unit,
  final HirFunction function,
  List<FormalParameterElement> parameters, {

  /// The class of the object that the function's first parameter is.
  final ClassElement? receiverClass,
}) {
  final _entry = HirBlock(function.parameters);
  late HirBlock _block = _entry;
  final _types = <VariableElement, HirType>{};
  final _values = <VariableElement, HirValue>{};

  this {
    final given = _entry.parameters.skip(receiverClass == null ? 0 : 1);
    for (final (i, value) in given.indexed) {
      declare(parameters[i], value.type);
      assign(parameters[i], value);
    }
  }

  /// The object that `this` is, where there is one.
  HirValue? get receiver =>
      receiverClass == null ? null : _entry.parameters.first;

  /// Gives [function] the blocks that can run.
  void finish() {
    end(function.result == null ? HirReturn() : HirUnreachable());
    function.define(
      reversePostorder(
        _entry,
        (block) => block.terminator!.edges.map((edge) => edge.target),
      ),
    );
  }

  T add<T extends HirInstruction>(T instruction) => _block.add(instruction);

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
  Join join(AstNode construct, [HirType? result]) {
    final variables = [
      for (final variable in assignedIn(construct))
        if (_types.containsKey(variable)) variable,
    ];
    final block = HirBlock([
      for (final variable in variables) _types[variable]!,
      ?result,
    ]);
    return Join._(block, variables);
  }

  HirEdge _edge(Join join, [HirValue? result]) =>
      HirEdge(join._block, [...join._variables.map(read), ?result]);

  void jump(Join join, [HirValue? result]) => end(HirJump(_edge(join, result)));

  /// Continues at [join], returning the value its predecessors supplied.
  HirValue? enter(Join join) {
    _block = join._block;
    for (final (i, variable) in join._variables.indexed) {
      _values[variable] = join._block.parameters[i];
    }
    return join._block.parameters.elementAtOrNull(join._variables.length);
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
