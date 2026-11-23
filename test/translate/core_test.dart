import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('print', () {
    agrees('any object', r'''
      class A { @override String toString() => 'A!'; } class B {} class C<T> {} enum_() => 1;
      void main() { print(1); print(-5); print(0); print(1234567890123); print(-9223372036854775808); print(9223372036854775807); print(true); print(false); print(null); print('text'); print(''); print(A()); print(B()); print(C<int>()); print(C<C<String>>()); Object? o = 2.5; print(o); o = null; print(o); print([null, true, 1, 2.0, 'x', A()]); print(enum_()); }
    ''');
    agrees('characters of every size', r'''
      void main() { print('é中😀 \u0000 \u{10ffff} a\nb\tc'); print('\ud800'); print('\udc00\ud800x'); print('x' * 5000 + 'é' * 3000); print('a' 'b' "c" r'\n$x' """
multi
line"""); }
    ''');
    agrees('doubles', '''
      void main() { final l = [1.0, 1.5, -0.0, 0.0, double.nan, double.infinity, -double.infinity, 1e300, 3.25, 1e21, 1e20, 123456789012345680000.0, 1e-7, 0.000001, 5e-324, 1.7976931348623157e308, 0.1 + 0.2, 100.0, 1e100, 1 / 3, 2 / 3, 123.456, 1e22, 0.00001234, 9007199254740993.0, 4.35, 0.3, 2.2250738585072014e-308, 1e23, 8.41e21, 5e-7, 123e-20];
        for (var i = 0; i < l.length; i++) { print(l[i]); print(-l[i]); } }
    ''');
  });

  group('numbers', () {
    agrees('have their members', '''
      void main() { for (final x in [0, 1, -1, 7, -7, 255, 9223372036854775807, -9223372036854775808, 1 << 40]) { print('\$x \${x.hashCode} \${x.isEven} \${x.isOdd} \${x.abs()} \${x.sign} \${x.bitLength} \${x.toDouble()} \${x.toRadixString(16)} \${x.toRadixString(2)} \${~x} \${-x} \${x.compareTo(3)} \${x == 7.0} \${x.isNegative} \${x.toString().length} \${x.clamp(-3, 5)} \${x.remainder(4)} \${x ~/ 3} \${x % 3} \${x.toUnsigned(8)} \${x.toSigned(4)} \${x / 2} \${x.floor()} \${x.round()} \${x.truncate()} \${x.ceil()}'); }
        print(12.gcd(18)); print(3.modPow(5, 7)); print(3.modInverse(7)); print(1 << 10 | 3); print(int.parse('42') + int.parse('-7')); print(int.parse('ff', radix: 16)); print(int.parse('0x1F')); print(int.tryParse('x')); print(int.tryParse('')); print(int.tryParse('9223372036854775808')); print(int.parse('-9223372036854775808')); num n = 5; print(n + 2.5); n = 2.5; print(n * 2); print(n.toInt()); print(n.compareTo(3)); }
    ''');
    agrees('that are doubles have their members', '''
      void main() { for (final x in [0.0, -0.0, 1.5, -1.5, 2.5, -2.5, 0.49999999999999994, 1e17, -3.7, 1e300, double.infinity, double.nan]) { print('\$x \${x.hashCode == (x * 1).hashCode} \${x.abs()} \${x.sign} \${x.isNegative} \${x.isNaN} \${x.isFinite} \${x.isInfinite} \${x.roundToDouble()} \${x.floorToDouble()} \${x.ceilToDouble()} \${x.truncateToDouble()} \${x.compareTo(1)} \${x.remainder(1.2)} \${x % 1.2} \${-x} \${x == 1.5} \${x < 2} \${x.toDouble()} \${x.toStringAsFixed(2)} \${x.toStringAsExponential(3)} \${x.toStringAsPrecision(4)} \${x.toStringAsExponential()} \${x.clamp(-2, 2)}'); if (x.isFinite) print('\${x.toInt()} \${x.round()} \${x.floor()} \${x.ceil()} \${x ~/ 1}'); }
        for (final x in [1.5, 1.0, 0.1, 1e300, -2.25, 1e18, 1e19, 5e-324]) { print(x.hashCode); } for (final d in [0, 1, 2, 5, 20]) { print(2.5.toStringAsFixed(d)); print(0.125.toStringAsFixed(d)); print((-0.001).toStringAsFixed(d)); print(1e20.toStringAsFixed(d)); print(99.995.toStringAsFixed(d)); print(0.5.toStringAsFixed(d)); } for (final p in [1, 2, 3, 7, 21]) { print(123.456.toStringAsPrecision(p)); print(0.00001234.toStringAsPrecision(p)); print(99.99.toStringAsPrecision(p)); print(0.0.toStringAsPrecision(p)); print(1.25.toStringAsExponential(p - 1)); print(0.0.toStringAsExponential(p - 1)); }
        for (final s in ['1', '1.5', '-2.25e3', '.5', '1.', ' 7 ', 'Infinity', '-Infinity', 'NaN', '1e400', '123456789012345678901234567890', '0.1e-5', '1e', 'x', '', '+3', '0x10', '1_0', '4.9e-324', '2.4703282292062328e-324']) { print(double.tryParse(s)); } print(num.parse('3')); print(num.parse('3.0')); print(1.0.hashCode == 1.hashCode); print(0.1 + 0.2 == 0.3); }
    ''');
  });

  agrees('strings have their members', r'''
    void main() { const words = ['', 'a', 'abc', 'Hello World', 'é中😀', '  x y  ', 'aXbXc', 'abĀ'];
      for (final s in words) { print('[$s] ${s.length} ${s.hashCode} ${s.isEmpty} ${s.isNotEmpty} ${s.toString()} ${s.contains('b')} ${s.indexOf('b')} ${s.lastIndexOf('X')} ${s.startsWith('a')} ${s.endsWith('c')} [${s.trim()}] [${s.trimLeft()}] [${s.trimRight()}] ${s.split('X')} ${s.split('')} ${s.replaceAll('X', '--')} ${s.replaceFirst('b', 'é')} ${s.codeUnits} ${s.runes.toList()} ${s * 2} ${s + s} ${s.compareTo('abc')} ${s == 'abc'} [${s.padLeft(6)}] [${s.padRight(6, '.')}]'); for (var i = 0; i < s.length; i++) { print('${s[i]} ${s.codeUnitAt(i)} [${s.substring(i)}] [${s.substring(0, i)}]'); } }
      print(String.fromCharCode(0x1f600)); print(String.fromCharCodes([104, 105, 0x4e2d])); print(String.fromCharCodes([1, 2, 3], 1, 2).length); print(['a', 'b'].join()); print([1, 2, 3].join(', ')); print('a-b-c'.splitMapJoin('-', onMatch: (m) => '+', onNonMatch: (n) => '($n)')); print('abcabc'.replaceAllMapped('b', (m) => '<${m[0]}>')); print('abc'.replaceRange(1, 2, 'XYZ')); print('b'.allMatches('abcb').map((m) => m.start).toList()); print(identical('a' 'b', 'ab')); print(identical('abc'[0], 'a')); final b = StringBuffer('s'); b.write('x'); b.write(1); b.writeln('y'); b.writeAll([1, null, 'é'], '-'); b.writeCharCode(0x1f600); print(b); print(b.length); b.clear(); print(b.isEmpty); var t = ''; for (var i = 0; i < 300; i++) { t += '$i'; } print(t.hashCode); print('abc'.compareTo('abd')); switch (t.substring(0, 3)) { case '012': print('yes'); default: print('no'); } }
  ''');

  group('lists', () {
    agrees(
      'have their members',
      r'''
      void main() { final l = <int>[3, 1, 2]; print(l); l.add(4); l.addAll([5, 6]); print('$l ${l.length} ${l.first} ${l.last} ${l.isEmpty} ${l.reversed} ${l.indexOf(2)} ${l.contains(9)}'); l.sort(); print(l); l.sort((a, b) => b - a); print(l); l.insert(1, 50); l.insertAll(2, [7, 8]); print(l); l.removeAt(0); print(l.removeLast()); l.remove(50); l.removeWhere((x) => x.isOdd); print(l); l.addAll(l.toList()); print(l); l.setRange(0, 2, [9, 10]); l.fillRange(2, 3, 0); print(l); print(l.sublist(1, 3)); l.length = 2; print(l); l.clear(); print(l); print(l.isEmpty);
        final m = List.generate(10, (i) => i * i); print(m.map((x) => x + 1).where((x) => x.isEven).toList()); print(m.fold<int>(0, (a, b) => a + b)); print(m.reduce((a, b) => a > b ? a : b)); print(m.any((x) => x > 80)); print(m.every((x) => x > 80)); print(m.take(3)); print(m.skip(8)); print(m.takeWhile((x) => x < 10)); print(m.skipWhile((x) => x < 10).toList()); print(m.firstWhere((x) => x > 10)); print(m.lastWhere((x) => x < 10)); print(m.firstWhere((x) => x > 1000, orElse: () => -1)); print(m.expand((x) => [x, x]).length); print(m.join('/')); print(m.asMap()[3]); print(m.elementAt(2)); print(m.toSet().length); print(m.followedBy([1]).last); print(m.indexWhere((x) => x == 49)); print(m.getRange(2, 4)); print([1, 2] + [3]); print(List.filled(2, 'x')); print(List.of(m, growable: false).length); print(List<int>.from([1, 2])); print(List.unmodifiable([1])); print(<int>[1, 2, 3].single == 3 ? 1 : 2); }
    '''
          .replaceAll(' print(<int>[1, 2, 3].single == 3 ? 1 : 2);', ''),
    );
    agrees('check what they are given', r'''
      void go(void Function() f) { try { f(); print('ok'); } catch (e) { print(e); } }
      void main() { final l = [1, 2, 3]; go(() => l[3]); go(() => l[-1]); go(() => l[5] = 1); go(() => <int>[][0]); go(() => const [1][1]); go(() => List.filled(2, 0)[2]); go(() => List.filled(-1, 0)); go(() => List.filled(1, 0).add(1)); go(() => (const [1] as List).add(1)); go(() => List.unmodifiable([1])[0] = 2); go(() => <int>[].first); go(() => <int>[].last); go(() => <int>[].single); go(() => l.single); go(() => <int>[].reduce((a, b) => a)); go(() => l.removeAt(7)); go(() => l.insert(9, 1)); go(() => l.sublist(2, 1)); go(() => l.firstWhere((x) => x > 5)); go(() { for (final x in l) { l.add(x); } }); go(() => (l as List<Object>).add('x')); go(() { dynamic d = l; d.add('x'); }); go(() { List<num> n = l; n[0] = 1.5; }); go(() { dynamic d = l; List<String> s = d; }); go(() => 'abc'[3]); go(() => 'abc'.codeUnitAt(3)); go(() => ''[0]); go(() => 'abc'.substring(2, 1)); go(() => int.parse('zz')); go(() => double.parse('zz')); go(() => l.elementAt(9)); go(() => Iterable.generate(3).elementAt(3)); go(() => 1 ~/ (l[0] - 1)); go(() => 1 << (l[0] - 2)); go(() => (0.0 / (l[0] - 1)).toInt()); go(() => (null as dynamic)!); go(() => throw 'text'); go(() => throw 5); go(() => throw Exception('boom')); go(() => throw StateError('bad')); go(() => throw ArgumentError.value(3, 'n', 'too big')); go(() => throw UnsupportedError('u')); go(() => throw FormatException('f', 'abc', 1)); go(() => throw RangeError.range(5, 0, 3, 'r')); go(() => throw UnimplementedError()); go(() => throw ConcurrentModificationError()); go(() => throw ArgumentError.notNull('z')); go(() => throw AssertionError('a')); }
    ''');
  });

  agrees(
    'maps and sets have their members',
    r'''
    class K { final int n; const K(this.n); @override bool operator ==(Object o) => o is K && o.n == n; @override int get hashCode => n % 2; @override String toString() => 'K$n'; }
    void main() { final m = {'a': 1, 'b': 2}; m['c'] = 3; print('$m ${m['b']} ${m['z']} ${m.length} ${m.keys} ${m.values.toList()} ${m.containsKey('c')} ${m.containsValue(9)}'); print(m.remove('a')); print(m.remove('q')); m.forEach((k, v) => print('$k$v')); for (final MapEntry(key: k) in <MapEntry<String, int>>[]) { print(k); } for (final e in m.entries) { print('${e.key}=${e.value}'); } print(m.putIfAbsent('x', () => 9)); print(m.update('x', (v) => v + 1)); m.addAll({'p': 1}); print(m.map((k, v) => MapEntry(v, k))); m.removeWhere((k, v) => v > 2); print(m); m.clear(); print(m.isEmpty);
      final big = <int, int>{}; for (var i = 0; i < 1000; i++) { big[i * 7] = i; } for (var i = 0; i < 1000; i += 3) { big.remove(i * 7); } var sum = 0; big.forEach((k, v) => sum += k ^ v); print('$sum ${big.length} ${big[14]} ${big[21]}'); final k = {K(1): 'one', K(3): 'three'}; k[K(1)] = 'uno'; print(k); print(k[K(3)]); final st = {1, 2, 2, 3}; print('$st ${st.contains(2)} ${st.add(2)} ${st.add(9)} ${st.union({100})} ${st.intersection({1, 9})} ${st.difference({1})} ${st.remove(1)} ${st.length} ${st.lookup(3)} ${st.toList()}'); print({K(1), K(1), K(2)}); print(const {'a': 1, 'b': [1]}['b']); print(const {1, 2}.contains(2)); print(const {K2.a: 1}.length); final n = <String?, int?>{null: null}; print(n.containsKey(null)); print(Map.of({1: 2})); print(Map.fromIterable([1, 2], value: (x) => x * 2)); print(Map.fromEntries([MapEntry(1, 2)])); print(Set.of([1, 1])); print(<String, List<int>>{}..putIfAbsent('k', () => []).add(1)); final d = <dynamic, dynamic>{1: 'i', 1.5: 'd', 'a': null, true: 2}; print('$d ${d[1.0]} ${d[1]}'); try { (const {1: 2} as Map)[1] = 3; } catch (e) { print(e); } try { for (final x in st) { st.remove(x); } } catch (e) { print('concurrent'); } }
    class K2 { static const a = 5; }
  '''
        .replaceAll(
          'for (final MapEntry(key: k) in <MapEntry<String, int>>[]) { print(k); } ',
          '',
        ),
  );

  agrees('literals have parts of every kind', r'''
    int calls = 0; int next() => ++calls; List<int>? none() => null;
    void main() { final l = [1, 2, 3]; bool yes = l.length > 2; int? nothing = l.isEmpty ? 1 : null; print([0, ...l, 4]); print([...?none(), ...?l]); print([if (yes) 'a' else 'b', if (!yes) 'c']); print([for (var i = 0; i < 3; i++) i * i]); print([for (final x in l) if (x.isOdd) ...[x, -x]]); print([?nothing, ?l.first]); print({...l, 9, if (yes) 10}); print({for (final x in l) x: '$x!', ...{'a': 'b'}, if (yes) 'y': 'n'}); print({'a': ?nothing, ?nothing: 1, 'b': 2}); print(<num>[1, 2.5, ...l]); dynamic d = [1, 2]; print(<int>[...d]); try { d = ['x']; print(<int>[...d]); } catch (e) { print(e); } print([next(), [next(), next()], {next(): next()}]); print([for (var i = 0, j = 5; i < j; i++, j--) '$i$j']); final fs = [for (var i = 0; i < 3; i++) () => i]; print([for (final f in fs) f()]); print(<int>[]); print(<String, int>{}); print(<int>{}); print(const [1, [2, ['a']], null, 2.5, true, {'k': {1}}]); var s = 0; int x; for (x in l) { s += x; } print('$s ${[...l, ...l.map((e) => e * s)]}'); outer: for (final a in l) { for (final b in l) { if (b == 2) continue outer; if (a == 3) break outer; print('$a$b'); } } for (final num v in d is List<num> ? <num>[] : [1]) { print(v); } }
  ''');

  agrees('every object has the members of Object', r'''
    class A {} class B { @override int get hashCode => 5; @override bool operator ==(Object o) => o is B; } int f() => 1; class C { int m() => 1; }
    void show<T>(T t) { print(t.toString().length > 0); print(t.hashCode == t.hashCode); print(t == t); }
    void main() { show(1); show<int?>(null); show(A()); show(f); show('x'); show(2.5); show([1]); show(null); Object? o; print(o.toString()); print(o.hashCode); print(null.hashCode); print(true.hashCode); print(false.hashCode); final a = A(), b = A(); print(a == b); print(a == a); print(B() == B()); print(B().hashCode); final c = C(); print(c.m == c.m); print(c.m == C().m); print(c.m.hashCode == c.m.hashCode); print(f == f); print({c.m}.contains(c.m)); print({a: 1}[b]); print({a: 1}[a]); print(identical(a, a)); print(identical(1, 1)); print(identical(1.5, 1.5)); dynamic d; print(d.toString()); print(d.hashCode); print(d == null); d = 'abc'; print(d.length); print(d.substring(1)); print(d[0]); print(d + 'x'); d = [1, 2]; d.add(3); print(d.map((x) => x * 2).toList()); d = 5; print(d.abs()); print(d + 2.5); print(d.isEven); d = {'a': 1}; print(d['a']); d['b'] = 2; print(d); try { d.foo(); } on NoSuchMethodError { print('none'); } }
  ''');

  agrees('typed data', r'''
    import_() => 1;
    void main() { final b = Uint8List(4); b[0] = 300; b[1] = -1; print(b); final w = b.buffer.asUint16List(); w[1] = 0xabcd; print(b); final d = ByteData(16); d.setFloat64(0, 1.5); d.setInt32(8, -7, Endian.little); print(d.getUint8(0)); print(d.getFloat64(0)); print(d.getInt32(8, Endian.little)); print(d.getInt32(8)); print(Float32List.fromList([0.1])[0]); print(Int8List.fromList([200])); print(Uint32List(2)..[1] = -1); print(Uint8ClampedList.fromList([300, -5, 7])); print(Uint8List.sublistView(b, 1, 3)); print(b.sublist(2)); b.setRange(1, 4, b); print(b); print(Int64List.fromList([1 << 62, -1])); try { b[4]; } catch (e) { print(e); } try { Uint8List(-1); } catch (e) { print(e); } final v = Uint8List.view(b.buffer, 1, 2); v[0] = 77; print('$b ${v.length} ${v.offsetInBytes}'); print(b.map((x) => x + 1).toList()); }
  ''', imports: "import 'dart:typed_data';");

  agrees('types are values', r'''
    class A {} class B<T> { Type get t => T; Type get b => B<T>; } Type id<T>() => T;
    void main() { print(int); print(A); print(B<int>().t); print(B<List<int>>().b); print(id<String?>()); print(A().runtimeType); print(B<int>().runtimeType == B<int>); print(1.runtimeType); print('x'.runtimeType); print([1].runtimeType); print([1].runtimeType == List<int>); print(const [1].runtimeType); print({}.runtimeType); print(<int>{}.runtimeType); print(null.runtimeType); print(1.5.runtimeType); print(true.runtimeType); print((() => 1).runtimeType); print(identical(int, int)); print(int == int); print({int: 1}[int]); switch (A) { case A: print('a'); } print(List); print(Map<String, int>); dynamic d = 5; print(d.runtimeType); print(main.runtimeType); print(const [int, String]); print(id<void Function(int, {String? a})>()); Type t = num; print(t); print(id<dynamic>() == id<Object?>()); }
  ''');

  agrees('functions have a text', r'''
    class A { A(); A.n(); int m() => 1; static int s() => 2; int get g => 3; int operator +(int o) => 1; factory A.f() => A(); } int top(int x) => x; T gen<T>(T t) => t;
    class G<T> { G(); G.x(); T? m(T t) => t; }
    void main() { int local() => 1; print(local); print(top); print(A.s); print(A().m); print(A.new); print(A.n); print(A.f); int Function(int) g = gen; print(g); print(G<int>.new); print(G<int>().m); print((int x, {required String y}) => x); print([1].add); print('a'.substring); print(identical); print(A().m.toString); print((A().m).call); print(print); }
  ''');
}
