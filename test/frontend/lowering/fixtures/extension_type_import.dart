import 'deferred_library.dart' as other;

other.E keep(other.E value) => value;
int run() => keep(other.E(3)).value;
