void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void main() {
  final one = BigInt.one;
  final n = (one << 240) + (one << 112) + BigInt.from(42);
  final d = (one << 80) + BigInt.from(7);
  final quotient = n ~/ d;
  final remainder = n.remainder(d);
  // Independent integer arithmetic vectors span several 32-bit limbs.
  check(
    quotient.toRadixString(16) == 'fffffffffffffffffff900000000000100000030',
    'large quotient',
  );
  check(
    remainder.toRadixString(16) == 'fffffffffff8fffffeda',
    'large remainder',
  );
  check(n == quotient * d + remainder, 'division identity');

  for (final left in [n, -n, d, -d, BigInt.zero]) {
    for (final right in [d, -d, n, -n, one, -one]) {
      final q = left ~/ right;
      final r = left.remainder(right);
      check(q * right + r == left, 'signed division identity');
      check(r.abs() < right.abs(), 'remainder magnitude');
      check(r == BigInt.zero || r.sign == left.sign, 'remainder sign');
      final modulo = left % right;
      check(modulo >= BigInt.zero && modulo < right.abs(), 'Euclidean modulo');
      check(
        (left - modulo).remainder(right) == BigInt.zero,
        'modulo congruence',
      );
    }
  }

  // Interleave other consumers of the shared cache before asking again.
  check(
    double.parse('1.23456789e100').toString() == '1.23456789e+100',
    'decimal cache consumer',
  );
  check(1.23456789.toStringAsFixed(7) == '1.2345679', 'decimal rounding');
  check(n ~/ d == quotient && n.remainder(d) == remainder, 'cache replacement');

  final factor = (one << 96) + one;
  check(
    (factor * BigInt.from(21)).gcd(factor * BigInt.from(-15)) ==
        factor * BigInt.from(3),
    'gcd',
  );
  check(
    BigInt.from(-3).pow(41).toString() == '-36472996377170786403',
    'integer power',
  );
  final prime = (one << 127) - one;
  final base = BigInt.from(17);
  check(
    base.modInverse(prime).toRadixString(16) ==
        'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f',
    'modular inverse',
  );
  check(
    base.modPow(BigInt.from(12345), prime).toRadixString(16) ==
        '1e58072fb17a4014a8e7cd868af0946a',
    'modular power',
  );

  for (final run in <void Function()>[
    () {
      n ~/ BigInt.zero;
    },
    () {
      n.remainder(BigInt.zero);
    },
    () {
      n % BigInt.zero;
    },
  ]) {
    var caught = false;
    try {
      run();
    } on UnsupportedError {
      caught = true;
    }
    check(caught, 'zero divisor');
  }
  check(n ~/ d == quotient, 'cache after failure');

  var total = 0;
  for (var i = 0; i < 4000; i++) {
    total += List<int>.filled(16, i).first;
  }
  check(total == 7998000, 'allocation loop');
  check(
    n ~/ d == quotient && n.remainder(d) == remainder,
    'cached state survives collection',
  );
  check(quotient * d + remainder == n, 'old results remain immutable');
  print('bigint:ok');
}
