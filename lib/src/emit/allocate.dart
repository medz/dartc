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

/// A word that is not stored.
final class const IsConstant(final int value) extends Location {
  @override
  bool operator ==(Object other) => other is IsConstant && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '#$value';
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

  /// Where values in registers are on the stack, too.
  final homes = <LirValue, OnStack>{};
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
      // A throw restores no registers.
      if (current.crossesThrow) {
        _spill(current);
        continue;
      }
      final usable = [
        if (!current.crossesCall) ...set.volatile,
        ...set.preserved,
      ];
      final free = _preferred(current, usable, active);
      if (free != null) {
        active[free] = current;
        _take(current, bank, free);
        continue;
      }
      if (usable.isEmpty) {
        _spill(current);
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
      _take(current, bank, victim);
    }
  }

  /// A register for [interval] of those that are [usable], if one is free. It is
  /// one that saves copying, if there is such.
  int? _preferred(
    Interval interval,
    List<int> usable,
    Map<int, Interval> active,
  ) {
    for (final other
        in liveness.related[interval.value] ?? const <LirValue>[]) {
      if (locations[other] case InRegister(:final number)
          when usable.contains(number) && !active.containsKey(number)) {
        return number;
      }
    }
    return usable.where((r) => !active.containsKey(r)).firstOrNull;
  }

  void _take(Interval interval, RegisterBank bank, int register) {
    locations[interval.value] = InRegister(bank, register);
    // The collector looks for references only on the stack. It does not move
    // objects, so they are in registers as well.
    if (interval.crossesCall && interval.value.type == .ref) {
      homes[interval.value] = OnStack(.spill, spillCount++);
    }
  }

  void _spill(Interval interval) {
    final home = homes.remove(interval.value);
    locations[interval.value] = home ?? OnStack(.spill, spillCount++);
  }
}
