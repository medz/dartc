int sum(int limit) {
  var result = 0;
  for (var i = 1; i <= limit; i++) {
    result += i;
  }
  return result;
}

int main() => sum(10);
