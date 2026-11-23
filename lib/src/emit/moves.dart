import 'allocate.dart';

/// Copies a word from one location to another.
typedef Move = ({Location source, Location destination});

/// Orders [moves], which happen at once, into a sequence of single copies.
///
/// Destinations are distinct. [temporary] is neither a source nor a
/// destination; it holds one value while a cycle is broken.
List<Move> sequentialize(Iterable<Move> moves, Location temporary) {
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
    result.add((source: saved, destination: temporary));
    for (final (i, move) in pending.indexed) {
      if (move.source == saved) {
        pending[i] = (source: temporary, destination: move.destination);
      }
    }
  }
  return result;
}
