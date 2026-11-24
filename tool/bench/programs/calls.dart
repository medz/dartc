// Calls of functions, with integers.
int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

int ackermann(int m, int n) => m == 0
    ? n + 1
    : n == 0
    ? ackermann(m - 1, 1)
    : ackermann(m - 1, ackermann(m, n - 1));

void main() {
  print(fib(38));
  print(ackermann(2, 4000) + ackermann(3, 8));
}
