import 'package:dartc/lir.dart';

import '../allocate.dart';
import '../liveness.dart';
import '../moves.dart';
import 'assembler.dart';
import 'convention.dart';
import 'operations.dart';

/// Emits one function.
///
/// From the stack pointer up, a frame holds outgoing arguments, spilled
/// values, preserved registers and the saved frame and return addresses.
final class Arm64Function(
  final LirFunction function,
  final Arm64Assembler _assembler,
) {
  final _labels = <LirBlock, Label>{};
  late final _liveness = Liveness(function);
  late final _allocation = Allocation(_liveness, arm64Registers);
  late final _operations = Arm64Operations(_assembler);
  late final int _outgoing = _outgoingWords();
  late final List<InRegister> _saved = _savedRegisters();

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

  List<InRegister> _savedRegisters() {
    final used = _allocation.locations.values.toSet();
    return [
      for (final MapEntry(key: bank, value: set) in arm64Registers.entries)
        for (final number in set.preserved)
          if (InRegister(bank, number) case final register
              when used.contains(register))
            register,
    ];
  }

  int _outgoingWords() {
    var words = 0;
    for (final block in function.blocks) {
      for (final call in block.instructions.whereType<LirCall>()) {
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

  void _prologue() {
    _assembler
      ..pushFrame()
      ..addImmediate(Arm64Assembler.frame, Arm64Assembler.stack, 0);
    final bytes = (_savedOffset(_saved.length) + 15) & ~15;
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
      case Call(:final symbol, :final arguments):
        _call(instruction, arguments, () => _assembler.call(symbol));
      case CallIndirect(:final address, :final arguments):
        _call(
          instruction,
          arguments,
          () => _assembler.callRegister(calleeScratch),
          address: address,
        );
      case Alloc(:final size):
        _allocate(instruction, size);
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

  void _call(
    LirCall call,
    List<LirValue> arguments,
    void Function() transfer, {
    LirValue? address,
  }) {
    final outgoing = argumentLocations(call.signature, .outgoing);
    _move([
      for (final (i, argument) in arguments.indexed)
        _between(_place(argument), outgoing[i], argument.type!),
      if (address != null)
        _between(_place(address), const InRegister(.word, calleeScratch), .ptr),
    ]);
    transfer();
    if (call.type case final type?) {
      _move([_between(resultLocation(type), _place(call), type)]);
    }
  }

  /// Allocates zeroed memory, stopping the program if there is none.
  void _allocate(Alloc allocation, LirValue size) {
    const result = InRegister(.word, 0), second = InRegister(.word, 1);
    _move([_between(_place(size), second, .i64)]);
    final failed = Label(), done = Label();
    _assembler
      ..constant(result.number, 1)
      ..call(allocateSymbol)
      ..jumpIfZero(result.number, failed)
      ..jump(done)
      ..bind(failed)
      ..breakpoint()
      ..bind(done);
    _move([_between(result, _place(allocation), .ref)]);
  }

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
      case Throw() || Invoke():
        throw StateError('Unchecked terminator: $end');
    }
  }

  void _follow(LirEdge edge) {
    _move([
      for (final (i, argument) in edge.arguments.indexed)
        _between(
          _place(argument),
          _place(edge.target.parameters[i]),
          argument.type!,
        ),
    ]);
    _assembler.jump(_labels[edge.target]!);
  }
}
