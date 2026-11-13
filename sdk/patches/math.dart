import '../runtime/memory.dart';

@patch
class _Random {
  // shortcut: clock-only default seed, use entropy when target support exists.
  @patch
  static int _initialSeed() => _setupSeed(Memory.clock());
}

@patch
class _SecureRandom {
  @patch
  static int _getBytes(int count) => throw UnsupportedError(
    'No source of cryptographically secure random numbers available.',
  );
}
