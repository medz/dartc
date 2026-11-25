class P {
  final int x, y;
  const P(this.x, [this.y = 2]);
  P get flipped => P(y, x);
}

void main() {
  final p = P(1).flipped;
  number(p.x); // expect: 2
  number(p.y); // expect: 1
}

void number(int n) => print(n);
