import 'package:dartc/lir.dart';

import '../allocate.dart';
import '../liveness.dart';
import '../moves.dart';
import '../stack_maps.dart';
import '../support.dart';
import 'assembler.dart';
import 'convention.dart';
import 'operations.dart';

/// Holds the frame to continue in, like an argument.
const _resumedFrame = 9;

/// Emits one function.
///
/// From the stack pointer up, a frame holds outgoing arguments, spilled
/// values, preserved registers and the saved frame and return addresses.
final class Arm64Function(
  final LirFunction function,
  final Arm64Assembler _assembler,
) {
  final _labels = <LirBlock, Label>{};

  /// What the calls keep alive, and where they continue if they throw.
  final List<StackMap> stackMaps = [];
  final List<ThrowTarget> throwTargets = [];
  late final _liveness = Liveness(function);
  late final _allocation = Allocation(_liveness, arm64Registers);
  late final _operations = Arm64Operations(_assembler);
  late final int _outgoing = _outgoingWords();
  late final List<InRegister> _saved = _savedRegisters();

  /// Adds the code.
  void emit() {
    for (final block in _liveness.order) {
      _labels[block] = Label();
    }
    _prologue();
    for (final block in _liveness.order) {
      _assembler.bind(_labels[block]!);
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
      for (final MapEntry(key: bank, value: set) in arm64Registers.entries)
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
        final extra = argumentLocations(
          call.signature,
          .outgoing,
        ).whereType<OnStack>().length;
        if (extra > words) words = extra;
      }
    }
    return words;
  }

  int _savedOffset(int index) =>
      (_outgoing + _allocation.spillCount + index) * 8;

  late final int _frameBytes = (_savedOffset(_saved.length) + 15) & ~15;

  void _prologue() {
    _assembler
      ..pushFrame()
      ..addImmediate(Arm64Assembler.frame, Arm64Assembler.stack, 0);
    final bytes = _frameBytes;
    if (function.checksStack) _checkStack(bytes);
    if (bytes > 0) {
      _assembler
        ..constant(rightScratch, bytes)
        ..subStack(rightScratch);
    }
    for (final (i, register) in _saved.indexed) {
      _access(register, Arm64Assembler.stack, _savedOffset(i), store: true);
    }
    final incoming = argumentLocations(function.signature, .incoming);
    _move([
      for (final (i, parameter) in function.entry.parameters.indexed)
        _between(incoming[i], _place(parameter), parameter.type),
    ]);
  }

  /// Calls a function that throws unless the stack has [bytes] left.
  void _checkStack(int bytes) {
    final enough = Label();
    _assembler
      ..constant(rightScratch, bytes)
      ..sub(rightScratch, Arm64Assembler.frame, rightScratch)
      ..address(farScratch, stackLimitSymbol)
      ..load(farScratch, farScratch, 0)
      ..cmp(rightScratch, farScratch)
      ..cset(rightScratch, .lo)
      ..jumpIfZero(rightScratch, enough)
      ..call(stackOverflowSymbol);
    stackMaps.add(StackMap(_assembler.offset, const []));
    _assembler
      ..breakpoint()
      ..bind(enough);
  }

  void _epilogue() {
    for (final (i, register) in _saved.indexed) {
      _access(register, Arm64Assembler.stack, _savedOffset(i), store: false);
    }
    _assembler
      ..addImmediate(Arm64Assembler.stack, Arm64Assembler.frame, 0)
      ..popFrame()
      ..ret();
  }

  /// Loads or stores [register] at any frame offset.
  void _access(
    InRegister register,
    int base,
    int offset, {
    required bool store,
  }) {
    final number = register.number, float = register.bank == .float;
    if (offset <= Arm64Assembler.maxOffset) {
      store
          ? _assembler.store(number, base, offset, float: float)
          : _assembler.load(number, base, offset, float: float);
      return;
    }
    _assembler.constant(farScratch, offset);
    store
        ? _assembler.storeIndexed(number, base, farScratch, float: float)
        : _assembler.loadIndexed(number, base, farScratch, float: float);
  }

  void _accessStack(InRegister register, OnStack word, {required bool store}) {
    final (base, index) = switch (word.area) {
      // Above the saved frame and return addresses.
      .incoming => (Arm64Assembler.frame, word.index + 2),
      .outgoing => (Arm64Assembler.stack, word.index),
      .spill => (Arm64Assembler.stack, _outgoing + word.index),
    };
    _access(register, base, index * 8, store: store);
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
        final number = switch (bank) {
          .word => const [leftScratch, rightScratch, calleeScratch][slot],
          .float => const [
            leftFloatScratch,
            rightFloatScratch,
            leftFloatScratch,
          ][slot],
        };
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
        final number = bank == .word ? leftScratch : leftFloatScratch;
        compute(number);
        _accessStack(InRegister(bank, number), word, store: true);
    }
  }

  void _move(Iterable<Move> moves) {
    const temporaries = {
      RegisterBank.word: InRegister(.word, rightScratch),
      RegisterBank.float: InRegister(.float, rightFloatScratch),
    };
    const carrier = InRegister(.word, leftScratch);
    for (final move in sequentialize(moves, temporaries)) {
      switch ((move.source, move.destination)) {
        case (InRegister source, InRegister destination):
          move.bank == .word
              ? _assembler.mov(destination.number, source.number)
              : _assembler.fmov(destination.number, source.number);
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
          _move([_between(resultLocation(type), _place(call), type)]);
        }
      case Resume(:final frame, :final code, :final exception, :final trace):
        const address = InRegister(.word, _resumedFrame);
        const target = InRegister(.word, calleeScratch);
        _move([
          _between(_place(exception), const InRegister(.word, 0), .ref),
          _between(_place(trace), const InRegister(.word, 1), .ref),
          _between(_place(frame), address, .i64),
          _between(_place(code), target, .i64),
        ]);
        _assembler
          ..mov(Arm64Assembler.frame, _resumedFrame)
          ..jumpRegister(calleeScratch);
      case Store(:final base, :final index, :final value):
        final at = _use(base, 0);
        final by = index == null ? null : _use(index, 1);
        _operations.store(instruction, at, by, _use(value, 2));
      default:
        final operands = [
          for (final (i, input) in instruction.inputs.indexed) _use(input, i),
        ];
        _define(
          instruction,
          (result) => _operations.emit(instruction, result, operands),
        );
    }
  }

  /// Makes [call], leaving its result where calls leave it, and records what
  /// it keeps alive.
  void _transfer(LirCall call) {
    final outgoing = argumentLocations(call.signature, .outgoing);
    final (arguments, address) = switch (call) {
      Call(:final arguments) => (arguments, null),
      CallIndirect(:final arguments, :final address) => (arguments, address),
      Alloc(:final size) => ([size], null),
    };
    _move([
      for (final (i, argument) in arguments.indexed)
        _between(_place(argument), outgoing[i], argument.type!),
      if (address != null)
        _between(_place(address), const InRegister(.word, calleeScratch), .ptr),
    ]);
    switch (call) {
      case Call(:final symbol):
        _assembler.call(symbol);
      case CallIndirect():
        _assembler.callRegister(calleeScratch);
      case Alloc():
        _assembler.call(allocateSymbol);
    }
    stackMaps.add(StackMap(_assembler.offset, _references(call)));
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
          _move([_between(_place(value), resultLocation(type), type)]);
        }
        _epilogue();
      case Jump(:final edge):
        _follow(edge);
      case Branch(:final condition, :final ifTrue, :final ifFalse):
        final otherwise = Label();
        _assembler.jumpIfZero(_use(condition, 0), otherwise);
        _follow(ifTrue);
        _assembler.bind(otherwise);
        _follow(ifFalse);
      case Unreachable():
        _assembler.breakpoint();
      case Throw(:final exception, :final trace):
        _move([
          _between(_place(exception), const InRegister(.word, 0), .ref),
          _between(_place(trace), const InRegister(.word, 1), .ref),
        ]);
        _assembler.call(throwSymbol);
        stackMaps.add(StackMap(_assembler.offset, const []));
        _assembler.breakpoint();
      case final Invoke invoke:
        _invoke(invoke);
    }
  }

  /// Makes a call and continues on one of its edges.
  void _invoke(Invoke invoke) {
    final Invoke(:call, :onReturn, :onThrow) = invoke;
    _transfer(call);
    final returnOffset = _assembler.offset;
    _follow(onReturn, [if (call.type case final type?) resultLocation(type)]);
    // The frame is found here again, without the stack it reached down to.
    throwTargets.add(ThrowTarget(returnOffset, _assembler.offset));
    _assembler
      ..constant(rightScratch, _frameBytes)
      ..sub(rightScratch, Arm64Assembler.frame, rightScratch)
      ..addImmediate(Arm64Assembler.stack, rightScratch, 0);
    _follow(onThrow, const [InRegister(.word, 0), InRegister(.word, 1)]);
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
    _assembler.jump(_labels[edge.target]!);
  }
}
