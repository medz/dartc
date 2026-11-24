import 'package:dartc/lir.dart';

import 'allocate.dart';
import 'liveness.dart';
import 'machine.dart';
import 'moves.dart';
import 'selection.dart';
import 'stack_maps.dart';
import 'support.dart';

/// Emits one function.
final class FunctionEmitter(
  final LirFunction function,
  final Machine _machine,
) {
  final _labels = <LirBlock, CodeLabel>{};
  late final _registers = _machine.registers;

  /// What the calls keep alive, and where they continue if they throw.
  final List<StackMap> stackMaps = [];
  final List<ThrowTarget> throwTargets = [];
  late final _selection = Selection(function, _machine);
  late final _liveness = Liveness(function, _selection);
  late final _allocation = Allocation(_liveness, _registers.values);
  late final int _outgoing = _outgoingWords();
  late final List<InRegister> _saved = _savedRegisters();

  /// Adds the code.
  void emit() {
    for (final block in _liveness.order) {
      _labels[block] = _machine.label();
    }
    _prologue();
    final order = _liveness.order;
    for (final (i, block) in order.indexed) {
      _next = order.elementAtOrNull(i + 1);
      _machine.bind(_labels[block]!);
      for (final instruction in block.instructions) {
        if (!_selection.isFolded(instruction)) _instruction(instruction);
      }
      _terminator(block.terminator!);
    }
  }

  /// The block whose code comes next.
  LirBlock? _next;

  /// The registers that callers rely on and this function changes.
  ///
  /// A throw caught here skips the functions that would restore the others.
  List<InRegister> _savedRegisters() {
    final used = _allocation.locations.values.toSet();
    final catches = function.blocks.any((block) => block.terminator is Invoke);
    return [
      for (final MapEntry(key: bank, value: set) in _registers.values.entries)
        for (final number in set.preserved)
          if (InRegister(bank, number) case final register
              when catches || used.contains(register))
            register,
    ];
  }

  int _outgoingWords() {
    var words = 0;
    for (final block in function.blocks) {
      for (final call in callsOf(block)) {
        final extra = _registers
            .argumentLocations(call.signature, .outgoing)
            .whereType<OnStack>()
            .length;
        if (extra > words) words = extra;
      }
    }
    return words;
  }

  int _savedOffset(int index) =>
      (_outgoing + _allocation.spillCount + index) * 8;

  late final int _frameBytes = (_savedOffset(_saved.length) + 15) & ~15;

  void _prologue() {
    _machine.enter(
      _frameBytes,
      checksStack: function.checksStack,
      onCheck: () => stackMaps.add(StackMap(_machine.offset, const [])),
    );
    for (final (i, register) in _saved.indexed) {
      _accessSaved(i, register, store: true);
    }
    final incoming = _registers.argumentLocations(
      function.signature,
      .incoming,
    );
    _move([
      for (final (i, parameter) in function.entry.parameters.indexed)
        ..._into(parameter, incoming[i]),
    ]);
  }

  void _epilogue() {
    for (final (i, register) in _saved.indexed) {
      _accessSaved(i, register, store: false);
    }
    _machine.leave();
  }

  void _accessSaved(int index, InRegister register, {required bool store}) =>
      _machine.access(
        register,
        _savedOffset(index),
        fromFrame: false,
        store: store,
      );

  void _accessStack(InRegister register, OnStack word, {required bool store}) {
    final (fromFrame, index) = switch (word.area) {
      // Above the saved frame and return addresses.
      .incoming => (true, word.index + 2),
      .outgoing => (false, word.index),
      .spill => (false, _outgoing + word.index),
    };
    _machine.access(register, index * 8, fromFrame: fromFrame, store: store);
  }

  /// Where [value] is.
  Location _place(LirValue value) =>
      _allocation.locations[value] ??
      switch (Selection.constantOf(value)) {
        final constant? => IsConstant(constant),
        null => throw StateError('A value has no place.'),
      };

  /// What copies [value] from [source] to where it is.
  List<Move> _into(LirValue value, Location source) => [
    // Parameters that nothing uses are nowhere.
    if (_allocation.locations[value] case final place?)
      _between(source, place, value.type!),
    if (_allocation.homes[value] case final home?)
      _between(source, home, value.type!),
  ];

  static Move _between(Location source, Location destination, LirType type) =>
      (source: source, destination: destination, bank: .of(type));

  /// The register holding [value], loading it into scratch [slot] if spilled.
  int _use(LirValue value, int slot) {
    switch (_place(value)) {
      case InRegister(:final number):
        return number;
      case IsConstant(value: final constant):
        final number = _registers.operands[RegisterBank.word]![slot];
        _machine.constant(number, constant);
        return number;
      case final OnStack word:
        final bank = RegisterBank.of(value.type!);
        final number = _registers.operands[bank]![slot];
        _accessStack(InRegister(bank, number), word, store: false);
        return number;
    }
  }

  /// Computes [value] into its own register, or through one to its spill.
  void _define(LirValue value, void Function(int register) compute) {
    switch (_place(value)) {
      case final InRegister register:
        compute(register.number);
        if (_allocation.homes[value] case final home?) {
          _accessStack(register, home, store: true);
        }
      case IsConstant():
        throw StateError('A constant is computed.');
      case final OnStack word:
        final bank = RegisterBank.of(value.type!);
        final number = _registers.operands[bank]!.first;
        compute(number);
        _accessStack(InRegister(bank, number), word, store: true);
    }
  }

  void _move(Iterable<Move> moves) {
    final temporaries = {
      for (final MapEntry(key: bank, value: number)
          in _registers.cycles.entries)
        bank: InRegister(bank, number),
    };
    final carrier = InRegister(.word, _registers.carrier);
    for (final move in sequentialize(moves, temporaries)) {
      switch ((move.source, move.destination)) {
        case (InRegister source, InRegister destination):
          _machine.copy(source, destination);
        case (InRegister source, OnStack destination):
          _accessStack(source, destination, store: true);
        case (OnStack source, InRegister destination):
          _accessStack(destination, source, store: false);
        case (OnStack source, OnStack destination):
          _accessStack(carrier, source, store: false);
          _accessStack(carrier, destination, store: true);
        case (IsConstant(:final value), InRegister(:final number)):
          _machine.constant(number, value);
        case (IsConstant(:final value), OnStack destination):
          _machine.constant(carrier.number, value);
          _accessStack(carrier, destination, store: true);
        case (_, IsConstant()):
          throw StateError('A constant is changed.');
      }
    }
  }

  void _instruction(LirInstruction instruction) {
    switch (instruction) {
      case final LirCall call:
        _transfer(call);
        if (call.type case final type?) {
          _move(_into(call, _registers.resultLocation(type)));
        }

      case Resume(:final frame, :final code, :final exception, :final trace):
        final [first, second] = _caught;
        _move([
          _between(_place(exception), first, .ref),
          _between(_place(trace), second, .ref),
          _between(
            _place(frame),
            InRegister(.word, _registers.resumedFrame),
            .i64,
          ),
          _between(_place(code), _callee, .i64),
        ]);
        _machine.resume();
      case Store(:final value):
        final [base, ...rest] = _selection.inputsOf(instruction);
        final at = _use(base, 0);
        final by = rest.length == 1 ? null : _use(rest.first, 1);
        _machine.store(
          instruction,
          at,
          by,
          _use(value, 2),
          isScaled: _selection.isScaled(instruction),
        );
      default:
        // What nothing uses has no place.
        if (!_allocation.locations.containsKey(instruction)) return;
        final operands = _operands(_selection.inputsOf(instruction));
        _define(
          instruction,
          (result) => _machine.operation(
            instruction,
            result,
            operands,
            immediate: _selection.immediateOf(instruction),
            isScaled: _selection.isScaled(instruction),
          ),
        );
    }
  }

  List<int> _operands(List<LirValue> inputs) => [
    for (final (i, input) in inputs.indexed) _use(input, i),
  ];

  List<InRegister> get _caught => [
    for (final number in _registers.caught) InRegister(.word, number),
  ];

  InRegister get _callee => InRegister(.word, _registers.callee);

  /// Makes [call], leaving its result where calls leave it, and records what
  /// it keeps alive.
  void _transfer(LirCall call) {
    final outgoing = _registers.argumentLocations(call.signature, .outgoing);
    final (arguments, address) = switch (call) {
      Call(:final arguments) => (arguments, null),
      CallIndirect(:final arguments, :final address) => (arguments, address),
      Alloc(:final size) => ([size], null),
    };
    _move([
      for (final (i, argument) in arguments.indexed)
        _between(_place(argument), outgoing[i], argument.type!),
      if (address != null) _between(_place(address), _callee, .ptr),
    ]);
    switch (call) {
      case Call(:final symbol):
        _machine.call(symbol, call.signature);
      case CallIndirect():
        _machine.callRegister(_registers.callee);
      case Alloc():
        _machine.call(allocateSymbol, call.signature);
    }
    stackMaps.add(StackMap(_machine.offset, _references(call)));
  }

  /// Where references alive across [call] are, from the frame address.
  List<int> _references(LirCall call) => [
    for (final value in _liveness.liveAfter(call))
      if (value.type == .ref)
        if (_allocation.homes[value] ?? _place(value) case OnStack(
          :final index,
        ))
          (_outgoing + index) * 8 - _frameBytes
        else
          throw StateError('A reference is not on the stack.'),
  ]..sort();

  void _terminator(LirTerminator end) {
    switch (end) {
      case Return(:final value):
        if (value != null) {
          final type = value.type!;
          _move([
            _between(_place(value), _registers.resultLocation(type), type),
          ]);
        }
        _epilogue();
      case Jump(:final edge):
        _follow(edge);
      case final Branch branch:
        _branch(branch);
      case Unreachable():
        _machine.breakpoint();
      case Throw(:final exception, :final trace):
        final [first, second] = _caught;
        _move([
          _between(_place(exception), first, .ref),
          _between(_place(trace), second, .ref),
        ]);
        _machine.call(throwSymbol, LirSignature([.ref, .ref]));
        stackMaps.add(StackMap(_machine.offset, const []));
        _machine.breakpoint();
      case final Invoke invoke:
        _invoke(invoke);
    }
  }

  /// Makes a call and continues on one of its edges.
  void _invoke(Invoke invoke) {
    final Invoke(:call, :onReturn, :onThrow) = invoke;
    _transfer(call);
    final returnOffset = _machine.offset;
    _follow(
      onReturn,
      supplied: [
        if (call.type case final type?) _registers.resultLocation(type),
      ],
      isLast: false,
    );
    // The frame is found here again, without the stack it reached down to.
    throwTargets.add(ThrowTarget(returnOffset, _machine.offset));
    _machine.restoreStack(_frameBytes);
    _follow(onThrow, supplied: _caught);
  }

  /// Whether branches on conditions may not reach all of the function.
  late final bool _isLong =
      function.blocks.fold(0, (sum, b) => sum + b.instructions.length + 8) >
      10000;

  void _branch(Branch branch) {
    final Branch(:ifTrue, :ifFalse) = branch;
    final comparison = _selection.comparisonOf(branch);
    final operands = _operands(_selection.endInputsOf(branch));
    void jump(CodeLabel label, {required bool holds}) => comparison == null
        ? _machine.jumpIfZero(operands.single, label, isZero: !holds)
        : _machine.jumpIf(
            comparison,
            operands,
            label,
            holds: holds,
            immediate: _selection.immediateOf(comparison),
          );
    final trueMoves = _movesFor(ifTrue), falseMoves = _movesFor(ifFalse);
    final canJumpIfTrue = trueMoves.isEmpty,
        canJumpIfFalse = falseMoves.isEmpty;
    if (!_isLong &&
        canJumpIfFalse &&
        (!canJumpIfTrue || ifTrue.target == _next)) {
      jump(_labels[ifFalse.target]!, holds: false);
      _follow(ifTrue);
    } else if (!_isLong && canJumpIfTrue) {
      jump(_labels[ifTrue.target]!, holds: true);
      _follow(ifFalse);
    } else {
      final otherwise = _machine.label();
      jump(otherwise, holds: false);
      _follow(ifTrue, isLast: false);
      _machine.bind(otherwise);
      _follow(ifFalse);
    }
  }

  /// The copies that following [edge] needs, whose target first receives what
  /// is at [supplied].
  List<Move> _movesFor(LirEdge edge, [List<Location> supplied = const []]) {
    final parameters = edge.target.parameters;
    return [
      for (final (i, source) in supplied.indexed)
        ..._into(parameters[i], source),
      for (final (i, argument) in edge.arguments.indexed)
        if (parameters[supplied.length + i] case final parameter
            when _allocation.locations.containsKey(parameter))
          ..._into(parameter, _place(argument)),
    ].where((move) => move.source != move.destination).toList();
  }

  /// Continues on [edge], whose target first receives what is at [supplied].
  void _follow(
    LirEdge edge, {
    List<Location> supplied = const [],
    bool isLast = true,
  }) {
    _move(_movesFor(edge, supplied));
    if (!isLast || edge.target != _next) {
      _machine.jump(_labels[edge.target]!);
    }
  }
}
