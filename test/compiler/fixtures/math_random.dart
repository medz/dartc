import 'dart:math';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void checkSeeded() {
  // Fixed SDK vectors protect its reused algorithm, not a cross-release stream.
  for (final (seed, integers, floating, boolean) in [
    (0, [0, 1, 1, 1010844852, 249241694, 410351881], 0.8502372762531368, false),
    (1, [0, 1, 2, 1563455612, 867044275, 2623941837], 0.9360953686036907, true),
    (
      -1,
      [0, 0, 1, 1648385005, 2064817445, 1090148994],
      0.12455107788047282,
      false,
    ),
    (
      -0x8000000000000000,
      [0, 0, 1, 1579164249, 2132682595, 2272104495],
      0.05735975820659567,
      true,
    ),
    (
      0x7fffffffffffffff,
      [0, 1, 0, 1436238347, 2130634896, 900376831],
      0.8935719462129976,
      true,
    ),
  ]) {
    final random = Random(seed);
    const bounds = [1, 2, 3, 0x7fffffff, 0x80000001, 0x100000000];
    for (var i = 0; i < bounds.length; i++) {
      check(random.nextInt(bounds[i]) == integers[i], 'seeded integer');
    }
    check(random.nextDouble() == floating, 'seeded double');
    check(random.nextBool() == boolean, 'seeded boolean');
  }

  final construct = Random.new;
  final reference = Random(42);
  final random = construct(42);
  final nextInt = random.nextInt;
  final nextDouble = random.nextDouble;
  final nextBool = random.nextBool;
  final dynamic dynamicRandom = random;
  for (var i = 0; i < 128; i++) {
    check(nextInt(0x80000001) == reference.nextInt(0x80000001), 'bound method');
    check(nextDouble() == reference.nextDouble(), 'double method');
    check(nextBool() == reference.nextBool(), 'boolean method');
    check(
      dynamicRandom.nextInt(1 << 32) == reference.nextInt(1 << 32),
      'dynamic method',
    );
    // Another generator must not mutate this generator's state.
    Random(i).nextInt(1 << 32);
  }

  for (final max in [
    0,
    -1,
    -0x8000000000000000,
    (1 << 32) + 1,
    0x7fffffffffffffff,
  ]) {
    var caught = false;
    try {
      nextInt(max);
    } on RangeError catch (error) {
      caught = true;
      check(
        error.invalidValue == max && error.start == 1 && error.end == 1 << 32,
        'range details',
      );
    }
    check(caught, 'invalid bound');
  }
  check(
    nextInt(1 << 32) == reference.nextInt(1 << 32),
    'invalid bounds preserve state',
  );

  for (final value in <Object?>[null, 1.0, '2', true]) {
    var caught = false;
    try {
      dynamicRandom.nextInt(value);
    } on TypeError {
      caught = true;
    }
    check(caught, 'dynamic bound type');
  }
  check(
    nextInt(1 << 32) == reference.nextInt(1 << 32),
    'type errors preserve state',
  );

  var total = 0;
  for (var i = 0; i < 4000; i++) {
    total += List<int>.filled(16, i).first;
  }
  check(total == 7998000, 'allocation loop');
  check(
    nextInt(1 << 32) == reference.nextInt(1 << 32),
    'state survives collection',
  );
}

void main() {
  checkSeeded();
  final construct = Random.new;
  final first = Random();
  for (final random in [first, Random(null), construct(), construct(null)]) {
    for (var i = 0; i < 64; i++) {
      final integer = random.nextInt(1 << 32);
      check(integer >= 0 && integer < 1 << 32, 'default integer range');
      final floating = random.nextDouble();
      check(floating >= 0.0 && floating < 1.0, 'default double range');
      random.nextBool();
    }
  }
  // The shared default-seed generator remains alive across collections.
  var total = 0;
  for (var i = 0; i < 4000; i++) {
    total += List<int>.filled(16, i).first;
  }
  check(total == 7998000, 'default allocation loop');
  check(Random().nextInt(1) == 0, 'default seed after collection');

  for (final create in [Random.secure, () => Random.secure()]) {
    final random = create();
    final nextInt = random.nextInt, nextDouble = random.nextDouble;
    final nextBool = random.nextBool;
    var bits = 0, complement = 0, seenTrue = false, seenFalse = false;
    for (var i = 0; i < 256; i++) {
      for (final bound in [1, 2, 3, 255, 256, 257, 0x80000001, 1 << 32]) {
        final value = nextInt(bound);
        check(value >= 0 && value < bound, 'secure integer range');
      }
      final value = nextInt(1 << 32);
      bits |= value;
      complement |= value ^ 0xffffffff;
      final floating = nextDouble();
      check(floating >= 0.0 && floating < 1.0, 'secure double range');
      if (nextBool()) {
        seenTrue = true;
      } else {
        seenFalse = true;
      }
    }
    check(bits == 0xffffffff && complement == 0xffffffff, 'secure bit width');
    check(seenTrue && seenFalse, 'secure boolean range');
    for (final bound in [0, -1, (1 << 32) + 1]) {
      var rejected = false;
      try {
        nextInt(bound);
      } on RangeError {
        rejected = true;
      }
      check(rejected, 'secure invalid bound');
    }
    final dynamic dynamicRandom = random;
    var caught = false;
    try {
      dynamicRandom.nextInt(1.0);
    } on TypeError {
      caught = true;
    }
    check(caught, 'secure dynamic bound');
    for (var i = 0; i < 4000; i++) {
      total += List<int>.filled(16, i).first;
    }
    check(nextInt(1) == 0, 'secure after collection');
    check(nextDouble() >= 0, 'secure entropy after collection');
  }
  print('random:ok');
}
