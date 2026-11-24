// Strings.
void main() {
  final buffer = StringBuffer();
  for (var i = 0; i < 300000; i++) {
    buffer.write('word${i % 1000} ');
  }
  final text = buffer.toString();
  final words = text.split(' ');
  final counts = <String, int>{};
  for (final word in words) {
    counts[word] = (counts[word] ?? 0) + 1;
  }
  print('${text.length} ${words.length} ${counts.length}');
  var sum = 0;
  for (var round = 0; round < 10; round++) {
    for (var i = 0; i < text.length; i++) {
      sum = (sum * 31 + text.codeUnitAt(i)) & 0xffffff;
    }
  }
  print(sum);
  var found = 0;
  for (var at = text.indexOf('word7'); at >= 0; at = text.indexOf('word7', at + 1)) {
    found++;
  }
  print(found);
  print(text.replaceAll('word', 'w').toUpperCase().hashCode != 0);
  print(words.map((word) => word.padLeft(8)).join('|').length);
  print(RegExp(r'word(\d)5\b').allMatches(text).length);
}
