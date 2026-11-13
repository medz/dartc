import 'dart:ffi';
import 'dart:math';

@Native<Int32 Function()>(assetId: 'entropy-test', symbol: 'deny')
external int denyEntropy();

void main() => checkUnavailable();

void checkUnavailable([Random? existing]) {
  final status = denyEntropy();
  if (status != 0) throw StateError('Cannot restrict entropy syscall: $status');
  for (final request in <Object Function()>[
    if (existing == null) ...[Random.secure, () => Random.secure()],
    if (existing != null) ...[
      () => existing.nextInt(2),
      existing.nextDouble,
      existing.nextBool,
    ],
  ]) {
    var rejected = false;
    try {
      request();
    } on UnsupportedError {
      rejected = true;
    }
    if (!rejected) throw StateError('Failed entropy was consumed');
  }
  // Only the ordinary generator may use a weak fallback when entropy fails.
  final random = Random();
  final value = random.nextInt(1 << 32);
  if (value < 0 || value >= 1 << 32) throw StateError('Default seed fallback');
  if (Random(0).nextInt(1) != 0) throw StateError('Explicit seed');
  print('entropy:unavailable');
}
