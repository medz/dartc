import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';

import 'aliases.dart';
import 'cold.dart';
import 'emitter.dart';
import 'facts.dart';

/// What replaces calls.
abstract interface class CallPolicy() {
  /// What [call] calls where its receiver is of some of [classes], if those are
  /// known, or of any class.
  Targets targetsOf(HirVirtualCall call, Set<HirClass>? classes);

  /// Whether integers without an object can receive calls of [selector].
  bool mayBeInteger(HirSelector selector);

  /// Whether calls of the runtime's test of types are answered where the
  /// class of the object decides them.
  bool get decidesTypes;

  /// Whether calls of [callee] are replaced by its body, where functions
  /// [around], the last one first, are replaced already. Larger ones are, too, if
  /// the parameters that the body branches on include one of which something
  /// [isKnown].
  bool inlines(
    HirFunction callee,
    List<HirFunction> around,
    bool Function(int parameter) isKnown,
  );
}

/// What a call calls for objects of some classes, and for all others, if that
/// is known. Nothing else can be called if that is all.
typedef Targets = ({
  List<(HirClass, HirFunction)> first,
  HirFunction? rest,
  bool isAll,
});

/// Where calls that throw continue, with what is given after the exception and
/// its trace.
typedef Handler = ({HirBlock target, List<HirValue> arguments});

Iterable<HirBlock> _successors(HirBlock block) =>
    block.terminator!.edges.map((edge) => edge.target);

/// Makes the body of [function] anew.
///
/// The old one has only blocks that can be reached.
List<HirBlock> rewrite(
  HirFunction function,
  HirModule module,
  CallPolicy policy,
) {
  final emitter = Emitter(module);
  final entry = emitter.newBlock(function.parameters);
  emitter.place = (block: entry, scope: Scope(), memory: Memory());
  _BodyCopy(
    function,
    emitter,
    policy,
    around: [function],
    handler: null,
    onReturn: (value) => emitter.end(HirReturn(value)),
  ).copy(entry.parameters);
  return emitter.blocks;
}

/// Adds the body of a function at a place.
final class _BodyCopy(
  final HirFunction _function,
  final Emitter _emitter,
  final CallPolicy _policy, {

  /// The functions whose bodies are around, with this one.
  required final List<HirFunction> around,

  /// Where the call is that this body replaces, if it does.
  final HirPlace? site,
  required final Handler? handler,

  /// Goes on with what the function returns.
  required final void Function(HirValue? value) onReturn,
}) {
  late final _dominators = Dominators(_function.entry, _successors);
  late final _aliases = findAliases(_function.entry, _dominators.order);
  final _values = <HirValue, HirValue>{};

  /// How many edges enter each block.
  late final _entering = () {
    final result = <HirBlock, int>{};
    for (final block in _dominators.order) {
      for (final next in _successors(block)) {
        result[next] = (result[next] ?? 0) + 1;
      }
    }
    return result;
  }();

  /// The new blocks of those that several edges enter.
  final _merges = <HirBlock, HirBlock>{};

  /// Where blocks go on that one edge enters.
  final _places = <HirBlock, Place>{};

  /// What is known at the end of blocks.
  final _ends = <HirBlock, Scope>{};

  void copy(List<HirValue> arguments) {
    for (final (i, parameter) in _function.entry.parameters.indexed) {
      _values[parameter] = arguments[i];
    }
    for (final block in _dominators.order) {
      if (!_enter(block)) continue;
      _isCold = _cold.contains(block);
      for (final instruction in block.instructions) {
        final value = _add(instruction);
        if (!_emitter.isReachable) break;
        if (value != null) _values[instruction] = value;
      }
      if (!_emitter.isReachable) continue;
      _ends[block] = _emitter.place!.scope;
      _terminate(block.terminator!);
    }
  }

  /// The blocks after which only throws come, which are not worth much code.
  late final _cold = coldBlocks(_dominators.order);

  bool _isCold = false;

  /// Goes to where [block] is, if it can be reached.
  bool _enter(HirBlock block) {
    if (block == _function.entry) return true;
    if (_places[block] case final place?) {
      _emitter.place = place;
      return true;
    }
    final merge = _merges[block];
    if (merge == null) {
      _emitter.place = null;
      return false;
    }
    var above = _dominators.parentOf(block);
    while (!_ends.containsKey(above)) {
      above = _dominators.parentOf(above);
    }
    final scope = Scope(_ends[above]);
    _emitter.place = (block: merge, scope: scope, memory: Memory());
    var next = 0;
    for (final parameter in block.parameters) {
      if (_aliases.containsKey(parameter)) continue;
      _values[parameter] = merge.parameters[next++];
    }
    return true;
  }

  HirValue _of(HirValue value) {
    final found = _values[value];
    if (found != null) return found;
    final alias = _aliases[value];
    return alias == null
        ? throw StateError('${_function.name}: a value is not known.')
        : _of(alias);
  }

  HirValue? _add(HirInstruction instruction) {
    final copy = copyInstruction(instruction, _of);
    if (copy is HirCalling) return _call(copy..place = _within(copy.place));
    return _emitter.add(copy);
  }

  /// [place] in this body, where it replaces a call.
  HirPlace? _within(HirPlace? place) =>
      site == null ? place : place?.within(site!) ?? site;

  /// Makes [call] and goes on after it, if code comes there.
  HirValue? _call(HirCalling call, {Handler? handler}) {
    final ending = handler ?? this.handler;
    if (call is HirVirtualCall) {
      final classes = _emitter.classesOf(call.receiver);
      final targets = _policy.targetsOf(call, classes);
      if (_isCold && targets.first.isNotEmpty) return _make(call, ending);
      return targets.first.isEmpty
          ? _callRest(call, targets, ending)
          : _choose(call, targets, ending);
    }
    if (call is HirCall) {
      if (_policy.decidesTypes) {
        if (_emitter.answerOf(call) case final answer?) return answer;
      }
      final target = call.target;
      if (target is HirFunction) {
        return _callDirectly(target, call.arguments, ending, call.place);
      }
    }
    return _make(call, ending);
  }

  HirValue? _callRest(HirVirtualCall call, Targets targets, Handler? ending) =>
      targets.rest == null
      ? _make(call, ending)
      : _callDirectly(targets.rest!, call.inputs, ending, call.place);

  HirValue? _callDirectly(
    HirFunction target,
    List<HirValue> arguments,
    Handler? ending,
    HirPlace? place,
  ) =>
      !_isCold && _policy.inlines(target, around, (i) => _isKnown(arguments[i]))
      ? _inline(target, arguments, ending, place)
      : _make(HirCall(target, arguments)..place = place, ending);

  /// Whether code for [value] may be simpler than for others.
  bool _isKnown(HirValue value) =>
      value is HirConst ||
      value.type == .reference && _emitter.classesOf(value)?.length == 1;

  /// Makes [call] for each of the classes of [targets] apart.
  HirValue? _choose(HirVirtualCall call, Targets targets, Handler? ending) {
    final scope = _emitter.place!.scope;
    final results = <(Place, HirValue?)>[];
    void collect(HirValue? value) {
      if (_emitter.place case final place?) results.add((place, value));
    }

    for (final (class_, target) in targets.first) {
      final condition = _emitter.add(
        HirHasClass(
          class_,
          call.receiver,
          mayBeInteger: _policy.mayBeInteger(call.selector),
        ),
      );
      if (condition is HirConst) {
        if (condition.value == false) continue;
        collect(_callDirectly(target, call.inputs, ending, call.place));
        break;
      }
      final here = _emitter.newBlock(), elsewhere = _emitter.newBlock();
      final Place(scope: before, :memory, block: _) = _emitter.place!;
      _emitter.end(HirBranch(condition, HirEdge(here), HirEdge(elsewhere)));
      Place placeOf(HirBlock block, {required bool holds}) => (
        block: block,
        scope: _scopeAfter(before, block, condition, holds: holds),
        memory: memory.copy(),
      );

      _emitter.place = placeOf(here, holds: true);
      collect(_callDirectly(target, call.inputs, ending, call.place));
      _emitter.place = placeOf(elsewhere, holds: false);
    }
    if (_emitter.isReachable) {
      if (targets.rest == null && targets.isAll) {
        _emitter.end(HirUnreachable());
      } else {
        collect(_callRest(call, targets, ending));
      }
    }
    return _merge(results, call.type, scope);
  }

  /// Makes [made], which is not replaced.
  HirValue? _make(HirCalling made, Handler? ending) {
    if (ending == null) return _emitter.add(made);
    final Place(:scope, :memory, block: _) = _emitter.place!;
    final next = _emitter.newBlock([?made.type]);
    _emitter
      ..addOutside(made)
      ..end(
        HirInvoke(
          made,
          HirEdge(next),
          HirEdge(ending.target, ending.arguments),
        ),
      );
    memory.clear();
    _emitter.place = (block: next, scope: Scope(scope), memory: memory);
    return next.parameters.firstOrNull;
  }

  HirValue? _inline(
    HirFunction callee,
    List<HirValue> arguments,
    Handler? handler,
    HirPlace? place,
  ) {
    final scope = _emitter.place!.scope;
    final returns = <(Place, HirValue?)>[];
    _BodyCopy(
      callee,
      _emitter,
      _policy,
      around: [...around, callee],
      site: place,
      handler: handler,
      onReturn: (value) {
        returns.add((_emitter.place!, value));
        _emitter.place = null;
      },
    ).copy(arguments);
    return _merge(returns, callee.result, scope);
  }

  /// Goes on after all of [ways] that have a value of [type], where what is
  /// known in [scope] is.
  HirValue? _merge(List<(Place, HirValue?)> ways, HirType? type, Scope scope) {
    if (ways.isEmpty) {
      _emitter.place = null;
      return null;
    }
    if (ways.length == 1) {
      final (place, value) = ways.single;
      _emitter.place = place;
      return value;
    }
    final after = _emitter.newBlock([?type]);
    for (final (place, value) in ways) {
      place.block.end(HirJump(HirEdge(after, [?value])));
    }
    _emitter.place = (block: after, scope: Scope(scope), memory: Memory());
    return after.parameters.firstOrNull;
  }

  /// The new block of [target], which several edges enter.
  HirBlock _mergeOf(HirBlock target) => _merges[target] ??= _emitter.newBlock([
    for (final parameter in target.parameters)
      if (!_aliases.containsKey(parameter)) parameter.type,
  ]);

  List<HirValue> _mergeArguments(HirBlock target, List<HirValue> arguments) => [
    for (final (i, parameter) in target.parameters.indexed)
      if (!_aliases.containsKey(parameter)) arguments[i],
  ];

  bool _hasOneEntry(HirBlock block) => _entering[block] == 1;

  void _bind(HirBlock target, Iterable<HirValue> arguments) {
    for (final (i, argument) in arguments.indexed) {
      _values[target.parameters[i]] = argument;
    }
  }

  /// Goes on at [target] from here.
  void _goTo(HirBlock target, List<HirValue> arguments) {
    if (_hasOneEntry(target)) {
      _bind(target, arguments);
      _places[target] = _emitter.place!;
      _emitter.place = null;
      return;
    }
    final merge = _mergeOf(target);
    _emitter.end(HirJump(HirEdge(merge, _mergeArguments(target, arguments))));
  }

  /// The edge to where code goes on for [edge], which is one of several of the
  /// block that ends here.
  HirEdge _edge(HirEdge edge, {HirValue? condition, bool holds = true}) {
    final target = edge.target;
    final arguments = edge.arguments.map(_of).toList();
    if (!_hasOneEntry(target)) {
      return HirEdge(_mergeOf(target), _mergeArguments(target, arguments));
    }
    final Place(:scope, :memory, block: _) = _emitter.place!;
    final next = _emitter.newBlock();
    _bind(target, arguments);
    final inner = _scopeAfter(scope, next, condition, holds: holds);
    _places[target] = (block: next, scope: inner, memory: memory.copy());
    return HirEdge(next);
  }

  /// What is known in [block], which is after [scope], if it is because
  /// [condition] [holds] or not.
  Scope _scopeAfter(
    Scope scope,
    HirBlock block,
    HirValue? condition, {
    required bool holds,
  }) {
    final inner = Scope(scope);
    if (condition is! HirInstruction) return inner;
    _emitter.assume(inner, condition, holds: holds);
    if (keyOf(condition) case final key?) inner[key] = _constant(block, holds);
    if (condition is HirCompare && condition.relation.isEquality) {
      final opposite = HirCompare(
        condition.relation == .equal ? .notEqual : .equal,
        condition.left,
        condition.right,
      );
      inner[keyOf(opposite)!] = _constant(block, !holds);
    }
    return inner;
  }

  HirConst _constant(HirBlock block, bool value) {
    final constant = block.add(HirConst(value));
    _emitter.addOutside(constant);
    return constant;
  }

  void _terminate(HirTerminator end) {
    switch (end) {
      case HirJump(:final edge):
        _goTo(edge.target, edge.arguments.map(_of).toList());
      case HirBranch():
        _branch(end);
      case HirReturn(:final value):
        onReturn(value == null ? null : _of(value));
      case HirThrow(:final exception, :final trace):
        final thrown = [_of(exception), _of(trace)];
        _emitter.end(switch (handler) {
          null => HirThrow(thrown[0], thrown[1]),
          (:final target, :final arguments) => HirJump(
            HirEdge(target, [...thrown, ...arguments]),
          ),
        });
      case HirInvoke(:final call, :final onReturn, :final onThrow):
        final caught = _handler(onThrow);
        final copy = copyInstruction(call, _of) as HirCalling;
        final result = _call(
          copy..place = _within(copy.place),
          handler: caught,
        );
        if (!_emitter.isReachable) return;
        _goTo(onReturn.target, [
          if (call.type != null) result!,
          ...onReturn.arguments.map(_of),
        ]);
      case HirExit(:final code):
        _emitter.end(HirExit(_of(code)));
      case HirUnreachable():
        _emitter.end(HirUnreachable());
    }
  }

  void _branch(HirBranch branch) {
    final HirBranch(:condition, :ifTrue, :ifFalse) = branch;
    final value = _of(condition);
    if (value is HirConst) {
      final edge = value.value == true ? ifTrue : ifFalse;
      _goTo(edge.target, edge.arguments.map(_of).toList());
      return;
    }
    _emitter.end(
      HirBranch(
        value,
        _edge(ifTrue, condition: value),
        _edge(ifFalse, condition: value, holds: false),
      ),
    );
  }

  /// Where what [edge] catches goes on.
  Handler _handler(HirEdge edge) {
    final target = edge.target;
    final arguments = edge.arguments.map(_of).toList();
    final thrown = target.parameters.take(2).toList();
    if (!_hasOneEntry(target)) {
      // What is thrown is never always the same.
      final given = _mergeArguments(target, [...thrown, ...arguments]);
      return (target: _mergeOf(target), arguments: given.sublist(2));
    }
    // Several calls may be made there, so only what dominates all is known.
    final scope = _emitter.place!.scope;
    final next = _emitter.newBlock(const [.reference, .reference]);
    _bind(target, [...next.parameters, ...arguments]);
    _places[target] = (block: next, scope: Scope(scope), memory: Memory());
    return (target: next, arguments: const []);
  }
}
