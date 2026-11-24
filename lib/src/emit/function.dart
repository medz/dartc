import 'package:dartc/lir.dart';

import 'allocate.dart';
import 'liveness.dart';
import 'machine.dart';
import 'moves.dart';
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
  late final _liveness = Liveness(function);
  late final _allocation = Allocation(_liveness, _registers.values);
  late final int _outgoing = _outgoingWords();
  late final List<InRegister> _saved = _savedRegisters();

  /// Adds the code.
  void emit() {
    for (final block in _liveness.order) {
      _labels[block] = _machine.label();
    }
    _prologue();
    for (final block in _liveness.order) {
      _machine.bind(_labels[block]!);
      block.instructions.forEach(_instruction);
      _terminator(block.terminator!);
    }
  }

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
        _between(incoming[i], _place(parameter), parameter.type),
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

  Location _place(LirValue value) => _allocation.locations[value]!;

  static Move _between(Location source, Location destination, LirType type) =>
      (source: source, destination: destination, bank: .of(type));

  /// The register holding [value], loading it into scratch [slot] if spilled.
  int _use(LirValue value, int slot) {
    switch (_place(value)) {
      case InRegister(:final number):
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
      case InRegister(:final number):
        compute(number);
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
      }
    }
  }

  void _instruction(LirInstruction instruction) {
    switch (instruction) {
      case final LirCall call:
        _transfer(call);
        if (call.type case final type?) {
          _move([
            _between(_registers.resultLocation(type), _place(call), type),
          ]);
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
      case Store(:final base, :final index, :final value):
        final at = _use(base, 0);
        final by = index == null ? null : _use(index, 1);
        _machine.store(instruction, at, by, _use(value, 2));
      default:
        final operands = [
          for (final (i, input) in instruction.inputs.indexed) _use(input, i),
        ];
        _define(
          instruction,
          (result) => _machine.operation(instruction, result, operands),
        );
    }
  }

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
        if (_place(value) case OnStack(:final index))
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
      case Branch(:final condition, :final ifTrue, :final ifFalse):
        final otherwise = _machine.label();
        _machine.jumpIfZero(_use(condition, 0), otherwise);
        _follow(ifTrue);
        _machine.bind(otherwise);
        _follow(ifFalse);
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
    _follow(onReturn, [
      if (call.type case final type?) _registers.resultLocation(type),
    ]);
    // The frame is found here again, without the stack it reached down to.
    throwTargets.add(ThrowTarget(returnOffset, _machine.offset));
    _machine.restoreStack(_frameBytes);
    _follow(onThrow, _caught);
  }

  /// Continues on [edge], whose target first receives what is at [supplied].
  void _follow(LirEdge edge, [List<Location> supplied = const []]) {
    final parameters = edge.target.parameters;
    _move([
      for (final (i, source) in supplied.indexed)
        _between(source, _place(parameters[i]), parameters[i].type),
      for (final (i, argument) in edge.arguments.indexed)
        _between(
          _place(argument),
          _place(parameters[supplied.length + i]),
          argument.type!,
        ),
    ]);
    _machine.jump(_labels[edge.target]!);
  }
}
