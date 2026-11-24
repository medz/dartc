// Lists of booleans and bytes.
import 'dart:typed_data';

int lists(int limit) {
  final isComposite = List.filled(limit + 1, false);
  var count = 0;
  for (var i = 2; i <= limit; i++) {
    if (isComposite[i]) continue;
    count++;
    for (var j = i + i; j <= limit; j += i) {
      isComposite[j] = true;
    }
  }
  return count;
}

int bytes(int limit) {
  final isComposite = Uint8List(limit + 1);
  var count = 0;
  for (var i = 2; i <= limit; i++) {
    if (isComposite[i] != 0) continue;
    count++;
    for (var j = i + i; j <= limit; j += i) {
      isComposite[j] = 1;
    }
  }
  return count;
}

void main() {
  for (var i = 0; i < 4; i++) {
    print(lists(4000000));
    print(bytes(4000000));
  }
}
