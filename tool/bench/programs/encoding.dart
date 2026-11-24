// The library for JSON and UTF-8.
import 'dart:convert';

void main() {
  final data = {
    'items': [
      for (var i = 0; i < 2000; i++)
        {'id': i, 'name': 'item é $i', 'price': i / 7, 'tags': ['a', 'b$i', null, true]},
    ],
  };
  var length = 0;
  for (var round = 0; round < 10; round++) {
    final bytes = utf8.encode(jsonEncode(data));
    length += bytes.length;
    final back = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    length += (back['items'] as List).length;
  }
  print(length);
}
