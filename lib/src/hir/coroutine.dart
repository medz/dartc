import 'package:dartc/graph.dart';

import 'block.dart';
import 'class.dart';
import 'copy.dart';
import 'instruction.dart';
import 'value.dart';

/// How functions that can be left in the middle are entered again.
///
/// They are given an object first, whose [state] tells where they go on. It
/// starts as 0. Its [frame] holds their values. The last parameters are what
/// they waited for, an exception or null, and its trace. The parameters before
/// those are the same each time.
final class const HirCoroutine({
  /// What functions call where they can be left.
  ///
  /// It gives its argument to their caller, and what they are entered with to
  /// them, unless that is an exception.
  required final HirCallable suspend,
  required final HirField state,
  required final HirField frame,
});

/// The body of a function, and the class that its frames are of, if it has any.
typedef HirCoroutineBody = ({List<HirBlock> blocks, HirClass? frame});

/// What a function called [name] does that starts as [entry] and calls the
/// suspending function of [coroutine], without such calls.
///
/// [entry] and the blocks after it are used up.
HirCoroutineBody splitCoroutine(
  HirBlock entry,
  HirCoroutine coroutine,
  String name,
) => _Splitter(entry, coroutine, name).split();

Iterable<HirBlock> _successors(HirBlock block) =>
    block.terminator!.edges.map((edge) => edge.target);

final class _Splitter(
  final HirBlock _entry,
  final HirCoroutine _coroutine,
  final String _name,
) {
  /// The results of calls that end their blocks now.
  final _results = <HirValue, HirValue>{};
  late final _order = reversePostorder(_entry, _successors);

  /// Where the function can be left, from state 1 on.
  late final _points = [
    for (final block in _order)
      if (block.terminator case HirInvoke(:final call) when _isSuspend(call))
        block,
  ];

  /// The fields of what is needed after the function is left.
  late final _fields = _findKept();
  late final _frameClass = HirClass('frame of $_name', null, _fields.values);
  late final _start = HirBlock(_entry.parameters.map((p) => p.type));
  late final _first = HirBlock();
  late final _blocks = {
    for (final block in _order)
      block: block == _entry
          ? _first
          : HirBlock(block.parameters.map((p) => p.type)),
  };

  /// What stands for values that are not kept.
  final _values = <HirValue, HirValue>{};

  bool _isSuspend(HirInstruction instruction) =>
      instruction is HirCall && instruction.target == _coroutine.suspend;

  HirCoroutineBody split() {
    for (final block in reversePostorder(_entry, _successors)) {
      _endAtCalls(block);
    }
    _values.addAll({
      for (final (i, parameter) in _entry.parameters.indexed)
        parameter: _start.parameters[i],
    });
    for (final block in _order) {
      _copy(block);
    }
    final resumes = [for (final block in _points) _resume(block)];
    _dispatch(resumes);
    return (
      blocks: reversePostorder(_start, _successors),
      frame: _fields.isEmpty ? null : _frameClass,
    );
  }

  /// Lets every block end where the function can be left.
  void _endAtCalls(HirBlock given) {
    var block = given;
    while (true) {
      final at = block.instructions.indexWhere(_isSuspend);
      if (at < 0) return;
      final call = block.instructions[at] as HirCall;
      final rest = HirBlock([call.type!]);
      _results[call] = rest.parameters.single;
      rest.instructions.addAll(block.instructions.skip(at + 1));
      rest.terminator = block.terminator;
      block.instructions.removeRange(at, block.instructions.length);
      final thrown = HirBlock(const [.reference, .reference]);
      final [exception, trace] = thrown.parameters;
      thrown.end(HirThrow(exception, trace));
      block.terminator = HirInvoke(call, HirEdge(rest), HirEdge(thrown));
      block = rest;
    }
  }

  HirValue _same(HirValue value) => _results[value] ?? value;

  Iterable<HirValue> _used(Iterable<HirValue> values) => values.map(_same);

  static Iterable<HirValue> _argumentsOf(HirBlock block) =>
      block.terminator!.edges.expand((edge) => edge.arguments);

  /// What is needed where a block starts.
  Map<HirBlock, Set<HirValue>> _findLive() {
    final live = {for (final block in _order) block: <HirValue>{}};
    bool changed;
    do {
      changed = false;
      for (final block in _order.reversed) {
        final found = {
          for (final next in _successors(block)) ...live[next]!,
          ..._used(_argumentsOf(block)),
          ..._used(block.terminator!.inputs),
        };
        for (final instruction in block.instructions.reversed) {
          found
            ..remove(instruction)
            ..addAll(_used(instruction.inputs));
        }
        found.removeAll(block.parameters);
        if (found.length == live[block]!.length) continue;
        live[block] = found;
        changed = true;
      }
    } while (changed);
    return live;
  }

  Map<HirValue, HirField> _findKept() {
    final live = _findLive();
    final kept = {
      for (final block in _points) ...[
        ..._used(_argumentsOf(block)),
        for (final edge in block.terminator!.edges) ...live[edge.target]!,
      ],
    }..removeAll(_entry.parameters);
    return {
      for (final (i, value) in kept.indexed)
        value: HirField('v$i', value.type!),
    };
  }

  /// Copies what [block] does.
  void _copy(HirBlock block) {
    final target = _blocks[block]!;
    final place = _Place(this, target);
    if (block == _entry) {
      if (_fields.isNotEmpty) {
        final frame = target.add(HirNew(_frameClass));
        target.add(HirStore(_coroutine.frame, _self, frame));
        place.frame = frame;
      }
    } else {
      for (final (i, parameter) in block.parameters.indexed) {
        place.define(parameter, target.parameters[i]);
      }
    }
    for (final instruction in block.instructions) {
      final made = target.add(copyInstruction(instruction, place.of));
      place.define(instruction, made);
    }
    final end = block.terminator!;
    if (_points.indexOf(block) case final point when point >= 0) {
      final given = place.of(end.inputs.single);
      final state = target.add(HirConst(point + 1));
      target
        ..add(HirStore(_coroutine.state, _self, state))
        ..end(HirReturn(given));
    } else {
      target.end(copyTerminator(end, place.of, (block) => _blocks[block]!));
    }
  }

  HirValue get _self => _start.parameters.first;

  /// Goes on where [block] left the function.
  HirBlock _resume(HirBlock block) {
    final HirInvoke(:onReturn, :onThrow) = block.terminator! as HirInvoke;
    final made = HirBlock();
    final place = _Place(this, made);
    final [..., value, exception, trace] = _start.parameters;
    HirEdge edge(HirEdge edge, List<HirValue> first) => HirEdge(
      _blocks[edge.target]!,
      [...first, ...edge.arguments.map(place.of)],
    );
    final none = made.add(HirNull());
    final isFine = made.add(HirCompare(.equal, exception, none));
    made.end(
      HirBranch(
        isFine,
        edge(onReturn, [value]),
        edge(onThrow, [exception, trace]),
      ),
    );
    return made;
  }

  /// Goes to where the state tells.
  void _dispatch(List<HirBlock> resumes) {
    final targets = [_first, ...resumes];
    final state = _start.add(HirLoad(_coroutine.state, _self));
    void choose(HirBlock block, int from, int to) {
      if (from + 1 == to) return block.end(HirJump(HirEdge(targets[from])));
      final middle = (from + to) ~/ 2, low = HirBlock(), high = HirBlock();
      final limit = block.add(HirConst(middle));
      final isLow = block.add(HirCompare(.less, state, limit));
      block.end(HirBranch(isLow, HirEdge(low), HirEdge(high)));
      choose(low, from, middle);
      choose(high, middle, to);
    }

    choose(_start, 0, targets.length);
  }
}

/// What values are in one block.
final class _Place(final _Splitter _splitter, final HirBlock _block) {
  HirValue? frame;
  final _own = <HirValue, HirValue>{};

  HirValue get _frame => frame ??= _block.add(
    HirLoad(_splitter._coroutine.frame, _splitter._self),
  );

  /// Says that [made] is [given] from here on.
  void define(HirValue given, HirValue made) {
    if (_splitter._fields[given] case final field?) {
      _own[given] = made;
      _block.add(HirStore(field, _frame, made));
    } else {
      _splitter._values[given] = made;
    }
  }

  HirValue of(HirValue given) {
    final value = _splitter._same(given);
    final field = _splitter._fields[value];
    if (field == null) return _splitter._values[value]!;
    return _own[value] ??= _block.add(HirLoad(field, _frame));
  }
}
