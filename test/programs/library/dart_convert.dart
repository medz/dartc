import 'dart:convert';

void main() {
  print(
    jsonEncode({
      'a': [1, 2.5, null, true, 'x"y\n'],
      'b': {'c': 'é'},
    }),
  ); // expect: {"a":[1,2.5,null,true,"x\"y\n"],"b":{"c":"é"}}
  print(
    jsonDecode('{"a": [1, 2.5, null, true, "x\\"y\\u00e9"], "b": {}}'),
  ); // expect: {a: [1, 2.5, null, true, x"yé], b: {}}
  print(
    utf8.encode('é中😀'),
  ); // expect: [195, 169, 228, 184, 173, 240, 159, 152, 128]
  print(utf8.decode([195, 169, 228, 184, 173])); // expect: é中
  print(base64Encode([1, 2, 3, 250])); // expect: AQID+g==
  print(base64Decode('AQID+g==')); // expect: [1, 2, 3, 250]
  print(latin1.encode('é')); // expect: [233]
  print(ascii.encode('abc')); // expect: [97, 98, 99]
  print(const LineSplitter().convert('a\nb\r\nc')); // expect: [a, b, c]
  print(
    JsonEncoder.withIndent('  ').convert({
      'a': 1,
      'b': [1, 2],
    }),
  );
  // expect: {
  // expect: "  \"a\": 1,"
  // expect: "  \"b\": ["
  // expect: "    1,"
  // expect: "    2"
  // expect: "  ]"
  // expect: }
  try {
    jsonDecode('{"a": }');
  } on FormatException catch (e) {
    print(e);
  }
  // expect: FormatException: Unexpected character (at character 7)
  // expect: {"a": }
  // expect: "      ^"
  // expect:
  print(
    htmlEscape.convert('<a href="x">&</a>'),
  ); // expect: &lt;a href=&quot;x&quot;&gt;&amp;&lt;&#47;a&gt;
  print(utf8.decode([0xff], allowMalformed: true)); // expect: �
  try {
    utf8.decode([0xff]);
  } on FormatException catch (e) {
    print(e.message);
  }
  // expect: Invalid UTF-8 byte
  print(
    jsonEncode([1.0, double.maxFinite, 'a/b']),
  ); // expect: [1.0,1.7976931348623157e+308,"a/b"]
  print(
    json.decode('[1e3, -0.5, 12345678901234567890]'),
  ); // expect: [1000.0, -0.5, 12345678901234567000.0]
}
