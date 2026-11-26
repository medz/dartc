import 'dart:io';

void main() {
  print(HttpDate.format(DateTime.utc(2020, 2, 29, 13, 5, 9))); // expect: Sat, 29 Feb 2020 13:05:09 GMT
  print(HttpDate.parse('Sat, 29 Feb 2020 13:05:09 GMT')); // expect: 2020-02-29 13:05:09.000Z
  try {
    HttpDate.parse('yesterday');
  } on HttpException catch (e) {
    print(e);
  }
  // expect: HttpException: Invalid HTTP date yesterday
  final type = ContentType.parse('text/html; charset=utf-8');
  print(type); // expect: text/html; charset=utf-8
  print((type.primaryType, type.subType, type.charset)); // expect: (text, html, utf-8)
  print(ContentType.json.mimeType); // expect: application/json
  print(Cookie('a', 'b')); // expect: a=b; HttpOnly
  final cookie = Cookie.fromSetCookieValue('x=y; Path=/; Max-Age=60; HttpOnly');
  print((
    cookie.name,
    cookie.value,
    cookie.path,
    cookie.maxAge,
    cookie.httpOnly,
  )); // expect: (x, y, /, 60, true)
  try {
    Cookie('a b', 'c');
  } on FormatException catch (e) {
    print(e.message);
  }
  // expect: Invalid character in cookie name, code unit: '32'
  print((HttpStatus.notFound, HttpHeaders.contentTypeHeader)); // expect: (404, content-type)
  final value = HeaderValue.parse('text/plain; q=1; a=b');
  print((
    value.value,
    value.parameters['a'],
    value.parameters.containsKey('q'),
  )); // expect: (text/plain, b, true)
  try {
    value.parameters['z'] = 'y';
  } on UnsupportedError catch (e) {
    print(e);
  }
  // expect: Unsupported operation: Cannot modify unmodifiable map
  print(HeaderValue('x', {'k': 'v'})); // expect: x; k=v
}
