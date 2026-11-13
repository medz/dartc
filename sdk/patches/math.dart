import '../runtime/entropy.dart' as entropy;
import '../runtime/memory.dart';

@patch
class _Random {
  @patch
  static int _initialSeed() =>
      _setupSeed(entropy.randomBytes(8) ?? Memory.clock());
}

@patch
class _SecureRandom {
  @patch
  static int _getBytes(int count) =>
      entropy.randomBytes(count) ??
      (throw UnsupportedError(
        'No source of cryptographically secure random numbers available.',
      ));
}
