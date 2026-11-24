import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('dart:core has', () {
    agrees('durations', r'''
    void main() { final d = Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4); print(d); print(d.inSeconds); print(d + Duration(days: 1)); print(d * 2); print(d < Duration(hours: 2)); print(-d); print(d.compareTo(Duration.zero)); print({d: 1}[Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4)]); }
  ''');

    agrees('big integers', r'''
    void main() { final a = BigInt.parse('123456789012345678901234567890'), b = BigInt.from(987654321); print(a + b); print(a * b); print(a ~/ b); print(a % b); print(-a); print(a.pow(3)); print(a.modPow(b, BigInt.from(1000007))); print(a.toRadixString(16)); print(a.compareTo(b)); print(a >> 10); print(a << 5); print(a.bitLength); print(a.gcd(b)); print((a & b) | (a ^ b)); print(a.toDouble()); print(BigInt.two.toInt()); print(a == BigInt.parse('123456789012345678901234567890')); print(a.hashCode == BigInt.parse('123456789012345678901234567890').hashCode); print(BigInt.tryParse('x')); print(BigInt.parse('-ff', radix: 16)); print(a.isEven); print(a.sign); print(b.modInverse(BigInt.from(1000000007))); }
  ''');

    agrees('addresses', r'''
    void main() { final u = Uri.parse('https://user@host.com:8080/a/b?x=1&y=2#frag'); print(u); print(u.host); print(u.port); print(u.path); print(u.queryParameters); print(u.fragment); print(u.resolve('../c')); print(Uri(scheme: 'http', host: 'x', path: '/p q')); print(Uri.encodeComponent('a b&c/é')); print(Uri.decodeComponent('a%20b')); print(u.pathSegments); print(Uri.encodeFull('a b?c=é')); print(u.replace(path: '/z')); print(Uri.file('/tmp/a b')); print(Uri.parse('a/b/../c').normalizePath()); print(Uri.splitQueryString('a=1&b=%20')); print(u == Uri.parse('$u')); }
  ''');

    agrees('dates', r'''
    void main() { final d = DateTime.utc(2024, 2, 29, 12, 30, 45, 123, 456); print(d); print(d.toIso8601String()); print(d.weekday); print(d.add(Duration(days: 1))); print(d.millisecondsSinceEpoch); print(DateTime.parse('2020-01-02T03:04:05Z')); print(d.difference(DateTime.utc(2024))); print(d.isBefore(DateTime.utc(2025))); print(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)); print(DateTime.now().year > 2000); final s = Stopwatch()..start(); print(s.elapsedMicroseconds >= 0); print(DateTime(2024, 6, 1, 10).hour); print(d == DateTime.utc(2024, 2, 29, 12, 30, 45, 123, 456)); print(d.compareTo(DateTime.utc(2000))); print(DateTime(2024, 7).timeZoneName.isNotEmpty); }
  ''');

    agrees('letters, weak references and the like', r'''
    class K { final int n; K(this.n); }
    void main() { print('straße ÀÉ ǆ İ ΑΣ'.toUpperCase()); print('ÀÉ İ ΑΣ ǅ'.toLowerCase()); print(Function.apply((int a, {int b = 1}) => a + b, [1], {#b: 5})); final x = Expando<String>('e'); final k = K(1); x[k] = 'v'; print(x[k]); print(x[K(1)]); print(x); print(Iterable.generate(3, (i) => i * 2)); print([1, 2].cast<num>()); print(List.castFrom<int, num>([1])); try { throw StateError('x'); } catch (e, s) { print(s is StackTrace); print((e as Error).stackTrace != null); } print(StackTrace.current is StackTrace); print(identityHashCode(k) == identityHashCode(k)); print(Error.safeToString('x\n')); print(Comparable.compare(1, 2)); print(['b', 'a']..sort()); print(const int.fromEnvironment('zz', defaultValue: 3)); print(const String.fromEnvironment('q')); print(WeakReference(k).target == k); Enum? e; print(e); print(Symbol('a')); }
  ''');
  });

  group('regular expressions', () {
    agrees('match', r'''
    void main() { final r = RegExp(r'(\w+)@(\w+)\.com'); print(r.hasMatch('joe@x.com')); final m = r.firstMatch('hi joe@site.com bye')!; print(m.group(0)); print(m[1]); print(m.start); print('a1b22c'.replaceAll(RegExp(r'\d+'), '#')); print('a1b22c'.split(RegExp(r'\d'))); print(RegExp('a|b').allMatches('cab').map((m) => m[0]).toList()); print(RegExp(r'^[a-z]+$', caseSensitive: false).hasMatch('ABC')); print(RegExp(r'(?<y>\d{4})').firstMatch('in 2024')!.namedGroup('y')); }
  ''');

    agrees('agree for many patterns', r'''
    const patterns = [r'a', r'a*', r'a+?', r'a{2}', r'a{2,}', r'a{1,2}?', r'(a)(b)?', r'(a|ab)(c|bcd)(d*)', r'(z)((a+)?(b+)?(c))*', r'[abc]', r'[^abc]', r'[a-c]+', r'[\d-x]', r'[\w.]+', r'\bfoo\b', r'\Boo', r'^a', r'a$', r'^$', r'(?:ab)+', r'(?=a)\w', r'(?!a)\w', r'(?<=a)b', r'(?<!a)b', r'(?<=(\d+)(\d+))x', r'(\w)\1', r'(?<x>a)\k<x>', r'a|b|', r'.', r'[\s\S]', r'\x41B\t', r'\0', r'\cA', r'[\b]', r'a.c', r'(a*)*', r'(a*)+', r'(?:a?)*?b', r'x{0}y', r'\d+(?=%)', r'(?:(a)|b)*', r'((a)|(b))+', r'a{', r'a{1', r'{', r'}', r']', r'\/', r'[]', r'[^]', r'é', r'[à-ü]+', r'\u{61}', r'(?<year>\d{4})-(?<m>\d\d)', r'(a(b(c)))', r'(?=(a+))a*b\1', r'(?!(a))\1b', r'\1(a)', r'[A-C]', r'\ud83d', r'[^\n]+', r'$^', r'a**', r'(', r')', r'[b-a]', r'a{2,1}', r'\', r'*', r'?', r'(?<a>x)(?<a>y)', r'(?z)', r'\k<q>', r'[', r'(?<=a+)b', r'(.)(?<=\1\1)', r'(?:)', r'[-a]', r'[a-]', r'[\]]', r'\w+@\w+\.com'];
    const inputs = ['aab', 'abc\nabc', 'foo 2024-05', 'zaacbbbcac', 'x😀é', ''];
    void main() { for (final p in patterns) { for (final flags in [0, 11]) { try { final r = RegExp(p, caseSensitive: flags & 1 == 0, multiLine: flags & 2 != 0, dotAll: flags & 4 != 0, unicode: flags & 8 != 0); final b = StringBuffer('$p $flags:'); for (final i in inputs) { for (final m in r.allMatches(i)) { b.write(' ${m.start}-${m.end}'); for (var g = 1; g <= m.groupCount; g++) { b.write('/${m[g]}'); } } b.write(';'); final q = r.matchAsPrefix(i, i.isEmpty ? 0 : 1); b.write(q == null ? '.' : '${q.end}'); } print(b); } on FormatException catch (e) { print('$p $flags ${e.runtimeType}'); } } } print(RegExp.escape(r'a.b*c')); print('aXbX'.replaceAllMapped(RegExp('x', caseSensitive: false), (m) => '<${m[0]}>')); print('a1b2'.split(RegExp(r'\d'))); print('abc'.replaceFirst(RegExp('b'), 'X')); print(RegExp(r'(?<n>.)').firstMatch('q')!.groupNames); print(RegExp('a', multiLine: true)); }
  ''', isLong: true);

    agrees('have flags', r'''
    void main() { for (var f = 0; f < 16; f++) print(RegExp('a', caseSensitive: f & 1 == 0, multiLine: f & 2 != 0, dotAll: f & 4 != 0, unicode: f & 8 != 0)); }
  ''');
  });

  agrees('dart:math', r'''
    void main() { print(max(1, 2)); print(min(1.5, 2)); print(pow(2, 10)); print(pow(2.5, 2)); print(pow(2, -1)); print(sqrt(2)); print(pi); print(sin(1).toStringAsFixed(12)); print(cos(1).toStringAsFixed(12)); print(tan(1).toStringAsFixed(12)); print(atan2(1, 2).toStringAsFixed(12)); print(exp(1).toStringAsFixed(12)); print(log(10).toStringAsFixed(12)); print(asin(0.5).toStringAsFixed(12)); print(acos(0.5).toStringAsFixed(12)); print(atan(0.5).toStringAsFixed(12)); final r = Random(42); print([for (var i = 0; i < 5; i++) r.nextInt(100)]); print(r.nextDouble()); print(r.nextBool()); print(Point(1, 2) + Point(3, 4)); print(Point(1, 2).distanceTo(Point(4, 6))); print(Rectangle(0, 0, 10, 20).containsPoint(Point(5, 5))); print(Random().nextInt(10) < 10); print(Rectangle(0, 0, 10, 20)); print([3, 1, 2]..shuffle(Random(1))); print(max(double.nan, 1)); print(min(-0.0, 0.0)); }
  ''', imports: "import 'dart:math';");

  agrees('dart:convert', r'''
    void main() { print(jsonEncode({'a': [1, 2.5, null, true, 'x"y\n'], 'b': {'c': 'é'}})); print(jsonDecode('{"a": [1, 2.5, null, true, "x\\"y\\u00e9"], "b": {}}')); print(utf8.encode('é中😀')); print(utf8.decode([195, 169, 228, 184, 173])); print(base64Encode([1, 2, 3, 250])); print(base64Decode('AQID+g==')); print(latin1.encode('é')); print(ascii.encode('abc')); print(const LineSplitter().convert('a\nb\r\nc')); print(JsonEncoder.withIndent('  ').convert({'a': 1, 'b': [1, 2]})); try { jsonDecode('{"a": }'); } on FormatException catch (e) { print(e); } print(htmlEscape.convert('<a href="x">&</a>')); print(utf8.decode([0xff], allowMalformed: true)); try { utf8.decode([0xff]); } on FormatException catch (e) { print(e.message); } print(jsonEncode([1.0, double.maxFinite, 'a/b'])); print(json.decode('[1e3, -0.5, 12345678901234567890]')); }
  ''', imports: "import 'dart:convert';");

  agrees('dart:collection', r'''
    final class E extends LinkedListEntry<E> { final int n; E(this.n); @override String toString() => 'E$n'; }
    void main() { final q = Queue<int>()..add(1)..addFirst(0)..addAll([5, 6]); print(q); print(q.removeFirst()); print(q.removeLast()); final s = SplayTreeMap<String, int>()..['b'] = 1..['a'] = 2; print(s); print(s.firstKey()); print(SplayTreeSet.of([3, 1, 2])); final h = HashMap<String, int>()..['x'] = 1..['yy'] = 2..['zzz'] = 3; print(h); print(HashSet.of([5, 3, 900, 17])); print(LinkedHashMap.of({1: 2})); final l = LinkedList<E>()..add(E(1))..add(E(2)); print(l); l.first.unlink(); print(l.length); print(UnmodifiableListView([1, 2])); print(ListQueue.of([1, 2, 3])); print(HashMap.identity()..[1] = 2); print(MapView({1: 2})); print(UnmodifiableMapView({1: 2})); for (final k in h.keys) { print(k); } print(LinkedHashSet<int>.identity()..add(1)); final m = MapBase.mapToString({1: 2}); print(m); print(IterableBase.iterableToShortString([1, 2], '(', ')')); final w = HashMap<int, int>(equals: (a, b) => a % 10 == b % 10, hashCode: (a) => a % 10); w[1] = 1; w[11] = 2; print(w); }
  ''', imports: "import 'dart:collection';");
}
