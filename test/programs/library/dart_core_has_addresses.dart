void main() {
  final u = Uri.parse('https://user@host.com:8080/a/b?x=1&y=2#frag');
  print(u); // expect: https://user@host.com:8080/a/b?x=1&y=2#frag
  print(u.host); // expect: host.com
  print(u.port); // expect: 8080
  print(u.path); // expect: /a/b
  print(u.queryParameters); // expect: {x: 1, y: 2}
  print(u.fragment); // expect: frag
  print(u.resolve('../c')); // expect: https://user@host.com:8080/c
  print(Uri(scheme: 'http', host: 'x', path: '/p q')); // expect: http://x/p%20q
  print(Uri.encodeComponent('a b&c/é')); // expect: a%20b%26c%2F%C3%A9
  print(Uri.decodeComponent('a%20b')); // expect: a b
  print(u.pathSegments); // expect: [a, b]
  print(Uri.encodeFull('a b?c=é')); // expect: a%20b?c=%C3%A9
  print(
    u.replace(path: '/z'),
  ); // expect: https://user@host.com:8080/z?x=1&y=2#frag
  print(Uri.file('/tmp/a b')); // expect: file:///tmp/a%20b
  print(Uri.parse('a/b/../c').normalizePath()); // expect: a/c
  print(Uri.splitQueryString('a=1&b=%20')); // expect: {a: 1, b:  }
  print(u == Uri.parse('$u')); // expect: true
}
