import 'package:dartc/lir.dart';

import '../allocate.dart';
import '../liveness.dart';
import '../moves.dart';
import 'assembler.dart';

/// The registers values may occupy.
///
/// Excluded: x8 and x15 to x17 are used below, x18 belongs to the system,
/// and x29 to x31 form the frame.
const arm64Registers = RegisterSet(
  volatile: [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14],
  preserved: [19, 20, 21, 22, 23, 24, 25, 26, 27, 28],
);

const _callee = 8, _left = 15, _right = 16, _far = 17;

/// The registers that hold a value only within one operation.
const arm64Scratch = [_callee, _left, _right, _far];

const _argumentRegisters = 8;

/// Emits one function.
///
/// The first eight arguments use x0 to x7 and the rest the caller's outgoing
/// words; the result uses x0. From the stack pointer up, a frame holds
/// outgoing arguments, spilled values, preserved registers and the saved
/// frame and return addresses.
final class Arm64Function(
  final LirFunction function,
  final Arm64Assembler _assembler,
) {
  final _labels = <LirBlock, Label>{};
  late final _liveness = Liveness(function);
  late final _allocation = Allocation(_liveness, arm64Registers);
  late final int _outgoing = _outgoingWords();
  late final List<int> _saved = [
    for (final register in arm64Registers.preserved)
      if (_allocation.locations.containsValue(InRegister(register))) register,
  ];

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

  int _outgoingWords() {
    var words = 0;
    for (final block in function.blocks) {
      for (final call in block.instructions.whereType<LirCall>()) {
        final extra = call.signature.parameters.length - _argumentRegisters;
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
        ..constant(_right, bytes)
        ..subStack(_right);
    }
    for (final (i, register) in _saved.indexed) {
      _access(register, Arm64Assembler.stack, _savedOffset(i), store: true);
    }
    _move([
      for (final (i, parameter) in function.entry.parameters.indexed)
        (
          source: _argument(i, .incoming),
          destination: _allocation.locations[parameter]!,
        ),
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

  static Location _argument(int index, StackArea area) =>
      index < _argumentRegisters
      ? InRegister(index)
      : OnStack(area, index - _argumentRegisters);

  /// Loads or stores [register] at any frame offset.
  void _access(int register, int base, int offset, {required bool store}) {
    if (offset <= Arm64Assembler.maxOffset) {
      store
          ? _assembler.store(register, base, offset)
          : _assembler.load(register, base, offset);
      return;
    }
    _assembler.constant(_far, offset);
    store
        ? _assembler.storeIndexed(register, base, _far)
        : _assembler.loadIndexed(register, base, _far);
  }

  void _accessStack(int register, OnStack word, {required bool store}) {
    final (base, index) = switch (word.area) {
      // Above the saved frame and return addresses.
      .incoming => (Arm64Assembler.frame, word.index + 2),
      .outgoing => (Arm64Assembler.stack, word.index),
      .spill => (Arm64Assembler.stack, _outgoing + word.index),
    };
    _access(register, base, index * 8, store: store);
  }

  /// The register holding [value], loading it into [scratch] if spilled.
  int _use(LirValue value, int scratch) {
    switch (_allocation.locations[value]!) {
      case InRegister(:final number):
        return number;
      case final OnStack word:
        _accessStack(scratch, word, store: false);
        return scratch;
    }
  }

  /// Computes [value] into its own register, or through one to its spill.
  void _define(LirValue value, void Function(int register) compute) {
    switch (_allocation.locations[value]!) {
      case InRegister(:final number):
        compute(number);
      case final OnStack word:
        compute(_left);
        _accessStack(_left, word, store: true);
    }
  }

  void _move(Iterable<Move> moves) {
    for (final move in sequentialize(moves, const InRegister(_right))) {
      switch ((move.source, move.destination)) {
        case (InRegister source, InRegister destination):
          _assembler.mov(destination.number, source.number);
        case (InRegister source, OnStack destination):
          _accessStack(source.number, destination, store: true);
        case (OnStack source, InRegister destination):
          _accessStack(destination.number, source, store: false);
        case (OnStack source, OnStack destination):
          _accessStack(_left, source, store: false);
          _accessStack(_left, destination, store: true);
      }
    }
  }

  void _instruction(LirInstruction instruction) {
    switch (instruction) {
      case ConstInt(:final value):
        _define(instruction, (d) => _assembler.constant(d, value));
      case SymbolAddress(:final symbol):
        _define(instruction, (d) => _assembler.address(d, symbol));
      case IntBinary(:final op, :final left, :final right):
        final l = _use(left, _left), r = _use(right, _right);
        _define(instruction, (d) => _integer(op, d, l, r));
      case Compare(:final relation, :final left, :final right):
        _assembler.cmp(_use(left, _left), _use(right, _right));
        _define(instruction, (d) => _assembler.cset(d, _condition(relation)));
      case Convert(:final operand):
        // Integers and addresses share one form.
        final source = _use(operand, _left);
        _define(instruction, (d) => _assembler.mov(d, source));
      case PtrAdd(:final base, :final offset):
        final l = _use(base, _left), r = _use(offset, _right);
        _define(instruction, (d) => _assembler.add(d, l, r));
      case Call(:final symbol, :final arguments):
        _call(instruction, arguments, () => _assembler.call(symbol));
      case CallIndirect(:final address, :final arguments):
        _call(
          instruction,
          arguments,
          () => _assembler.callRegister(_callee),
          address: address,
        );
      case ConstFloat() ||
          ConstNull() ||
          FloatBinary() ||
          FloatUnary() ||
          Load() ||
          Store() ||
          Alloc():
        throw StateError('Unchecked instruction: $instruction');
    }
  }

  void _integer(IntOp op, int d, int l, int r) {
    switch (op) {
      case .add:
        _assembler.add(d, l, r);
      case .sub:
        _assembler.sub(d, l, r);
      case .mul:
        _assembler.mul(d, l, r);
      case .div:
        _assembler.sdiv(d, l, r);
      case .rem:
        _assembler
          ..sdiv(_far, l, r)
          ..msub(d, _far, r, l);
      case .and:
        _assembler.and(d, l, r);
      case .or:
        _assembler.orr(d, l, r);
      case .xor:
        _assembler.eor(d, l, r);
      case .shl:
        _assembler.lsl(d, l, r);
      case .sar:
        _assembler.asr(d, l, r);
      case .shr:
        _assembler.lsr(d, l, r);
    }
  }

  static Condition _condition(Relation relation) => switch (relation) {
    .eq => .eq,
    .ne => .ne,
    .lt => .lt,
    .le => .le,
    .gt => .gt,
    .ge => .ge,
    .ult => .lo,
    .ule => .ls,
    .ugt => .hi,
    .uge => .hs,
  };

  void _call(
    LirCall call,
    List<LirValue> arguments,
    void Function() transfer, {
    LirValue? address,
  }) {
    _move([
      for (final (i, argument) in arguments.indexed)
        (
          source: _allocation.locations[argument]!,
          destination: _argument(i, .outgoing),
        ),
      if (address != null)
        (
          source: _allocation.locations[address]!,
          destination: const InRegister(_callee),
        ),
    ]);
    transfer();
    if (_allocation.locations[call] case final destination?) {
      _move([(source: const InRegister(0), destination: destination)]);
    }
  }

  void _terminator(LirTerminator end) {
    switch (end) {
      case Return(:final value):
        if (value != null) {
          _move([
            (
              source: _allocation.locations[value]!,
              destination: const InRegister(0),
            ),
          ]);
        }
        _epilogue();
      case Jump(:final edge):
        _follow(edge);
      case Branch(:final condition, :final ifTrue, :final ifFalse):
        final otherwise = Label();
        _assembler.jumpIfZero(_use(condition, _left), otherwise);
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
        (
          source: _allocation.locations[argument]!,
          destination: _allocation.locations[edge.target.parameters[i]]!,
        ),
    ]);
    _assembler.jump(_labels[edge.target]!);
  }
}
