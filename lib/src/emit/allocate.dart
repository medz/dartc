import 'package:dartc/lir.dart';

import 'liveness.dart';

/// Where a value lives.
sealed class const Location();

/// The separate sets of registers for words and for doubles.
enum RegisterBank() {
  word,
  float;

  /// The registers holding values of [type].
  factory of(LirType type) => type == .f64 ? float : word;
}

/// A machine register, numbered as the target encodes it.
final class const InRegister(final RegisterBank bank, final int number)
    extends Location {
  @override
  bool operator ==(Object other) =>
      other is InRegister && other.bank == bank && other.number == number;
  @override
  int get hashCode => Object.hash(bank, number);
  @override
  String toString() => '${bank.name}$number';
}

/// The words of a stack frame.
enum StackArea() {
  /// Arguments beyond the registers, written by the caller.
  incoming,

  /// Values without a register.
  spill,

  /// Arguments beyond the registers for a call made here.
  outgoing,
}

/// The [index]-th word of a stack area.
final class const OnStack(final StackArea area, final int index)
    extends Location {
  @override
  bool operator ==(Object other) =>
      other is OnStack && other.area == area && other.index == index;
  @override
  int get hashCode => Object.hash(area, index);
  @override
  String toString() => '${area.name}$index';
}

/// The registers of one bank a target offers to values.
final class const RegisterSet({
  /// Destroyed by every call.
  required final List<int> volatile,

  /// Preserved by every call.
  required final List<int> preserved,
});

/// One location for each value's whole life.
final class Allocation(
  final Liveness liveness,
  final Map<RegisterBank, RegisterSet> registers,
) {
  final locations = <LirValue, Location>{};
  int spillCount = 0;

  this {
    _scan();
  }

  /// Visits intervals by start, evicting the one that ends last.
  void _scan() {
    final intervals = liveness.intervals.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final inUse = {
      for (final bank in RegisterBank.values) bank: <int, Interval>{},
    };
    for (final current in intervals) {
      final bank = RegisterBank.of(current.value.type!);
      final active = inUse[bank]!, set = registers[bank]!;
      active.removeWhere((_, interval) => interval.end < current.start);
      // The collector looks for references only on the stack.
      if (current.crossesCall && current.value.type == .ref) {
        _spill(current);
        continue;
      }
      final usable = [
        if (!current.crossesCall) ...set.volatile,
        ...set.preserved,
      ];
      final free = usable.where((r) => !active.containsKey(r)).firstOrNull;
      if (free != null) {
        active[free] = current;
        locations[current.value] = InRegister(bank, free);
        continue;
      }
      final victim = usable.reduce(
        (a, b) => active[a]!.end >= active[b]!.end ? a : b,
      );
      final evicted = active[victim]!;
      if (evicted.end <= current.end) {
        _spill(current);
        continue;
      }
      _spill(evicted);
      active[victim] = current;
      locations[current.value] = InRegister(bank, victim);
    }
  }

  void _spill(Interval interval) =>
      locations[interval.value] = OnStack(.spill, spillCount++);
}
