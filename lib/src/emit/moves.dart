import 'allocate.dart';

/// Copies a value of one bank from one location to another.
typedef Move = ({Location source, Location destination, RegisterBank bank});

/// Orders [moves], which happen at once, into a sequence of single copies.
///
/// Destinations are distinct. [temporaries] gives a register of each bank that
/// is neither a source nor a destination, to hold a value of a broken cycle.
/// Values of different banks never share a location.
List<Move> sequentialize(
  Iterable<Move> moves,
  Map<RegisterBank, Location> temporaries,
) => [
  for (final bank in RegisterBank.values)
    ..._sequentializeBank(
      moves.where((move) => move.bank == bank),
      temporaries[bank]!,
    ),
];

List<Move> _sequentializeBank(Iterable<Move> moves, Location temporary) {
  final pending = [
    for (final move in moves)
      if (move.source != move.destination) move,
  ];
  final result = <Move>[];
  while (pending.isNotEmpty) {
    final ready = pending.indexWhere(
      (move) => pending.every((other) => other.source != move.destination),
    );
    if (ready >= 0) {
      result.add(pending.removeAt(ready));
      continue;
    }
    // Every destination is still needed: save one and read it from there.
    final saved = pending.first.destination;
    result.add((
      source: saved,
      destination: temporary,
      bank: pending.first.bank,
    ));
    for (final (i, move) in pending.indexed) {
      if (move.source == saved) {
        pending[i] = (
          source: temporary,
          destination: move.destination,
          bank: move.bank,
        );
      }
    }
  }
  return result;
}
