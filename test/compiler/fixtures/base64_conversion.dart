import 'dart:convert';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

bool rejects<T>(void Function() run) {
  try {
    run();
  } catch (error) {
    return error is T;
  }
  return false;
}

void churn() {
  var sum = 0;
  for (var i = 0; i < 4000; i++) {
    sum += List<int>.filled(16, i).first;
  }
  check(sum == 7998000, 'allocation loop');
}

String encodeChunks(
  Base64Codec codec,
  List<int> bytes,
  int split, {
  bool plainSink = false,
  bool finalSlice = false,
  bool collect = false,
}) {
  String? result;
  var closes = 0;
  void finish(String value) {
    result = value;
    closes++;
  }

  final output = plainSink
      ? ChunkedConversionSink<String>.withCallback(
          (chunks) => finish(chunks.join()),
        )
      : StringConversionSink.withCallback(finish);
  final input = codec.encoder.startChunkedConversion(output);
  final buffer = [-1, ...bytes, -1];
  input.addSlice(buffer, 1, split + 1, false);
  // addSlice must consume bytes before returning.
  buffer.fillRange(1, split + 1, 256);
  if (collect) churn();
  input.addSlice(buffer, split + 1, buffer.length - 1, finalSlice);
  if (!finalSlice) input.close();
  check(closes == 1, 'encoder output closure');
  return result!;
}

List<int> decodeChunks(
  String text,
  int split, {
  bool finalSlice = false,
  bool collect = false,
}) {
  List<int>? result;
  var closes = 0;
  final input = base64.decoder.startChunkedConversion(
    ByteConversionSink.withCallback((bytes) {
      result = bytes;
      closes++;
    }),
  );
  final padded = '!$text?';
  input.addSlice(padded, 1, split + 1, false);
  if (collect) churn();
  input.addSlice(padded, split + 1, padded.length - 1, finalSlice);
  if (!finalSlice) input.close();
  check(closes == 1, 'decoder output closure');
  return result!;
}

Future<void> main() async {
  // RFC 4648 section 10, plus its binary example and URL-safe alphabet.
  for (final (bytes, standard, url) in <(List<int>, String, String)>[
    ([], '', ''),
    ([102], 'Zg==', 'Zg=='),
    ([102, 111], 'Zm8=', 'Zm8='),
    ([102, 111, 111], 'Zm9v', 'Zm9v'),
    ([102, 111, 111, 98], 'Zm9vYg==', 'Zm9vYg=='),
    ([102, 111, 111, 98, 97], 'Zm9vYmE=', 'Zm9vYmE='),
    ([102, 111, 111, 98, 97, 114], 'Zm9vYmFy', 'Zm9vYmFy'),
    ([0x14, 0xfb, 0x9c, 3, 0xd9, 0x7e], 'FPucA9l+', 'FPucA9l-'),
    ([0xfb, 0xff], '+/8=', '-_8='),
  ]) {
    check(base64Encode(bytes) == standard, 'standard vector');
    check(base64Url.encode(bytes) == url, 'URL-safe vector');
    for (final encoded in {standard, url}) {
      check(
        base64Decode(encoded).join(',') == bytes.join(','),
        'decode vector',
      );
      for (var split = 0; split <= encoded.length; split++) {
        for (final last in [false, true]) {
          check(
            decodeChunks(encoded, split, finalSlice: last).join(',') ==
                bytes.join(','),
            'decoded split $split',
          );
        }
      }
    }
    for (final (codec, expected) in [(base64, standard), (base64Url, url)]) {
      for (var split = 0; split <= bytes.length; split++) {
        for (final plain in [false, true]) {
          for (final last in [false, true]) {
            check(
              encodeChunks(
                    codec,
                    bytes,
                    split,
                    plainSink: plain,
                    finalSlice: last,
                  ) ==
                  expected,
              'encoded split $split',
            );
          }
        }
      }
    }
  }

  check(base64.normalize('Zg') == 'Zg==', 'normalization adds padding');
  check(
    base64.normalize('x-_8%3d!', 1, 7) == 'x+/8=!',
    'normalization preserves outside slice',
  );
  for (var split = 0; split <= 8; split++) {
    check(
      decodeChunks('Zg%3D%3d', split, finalSlice: true).single == 102,
      'escaped padding split $split',
    );
  }
  check(base64.decoder.convert('!Zg==?', 1, 5).single == 102, 'decoder slice');
  check(
    rejects<RangeError>(() => base64.decoder.convert('Zg==', -1)) &&
        rejects<RangeError>(() => base64.normalize('Zg==', 0, 5)),
    'slice bounds',
  );
  for (final text in [
    'A',
    'Zg',
    'Zg=',
    'Zg===',
    'Zg==x',
    'Z g==',
    'Zg==\n',
    'Zh==',
    'Zm9=',
    'Zg%3',
    'Zg%2D%3D',
    '\u00ffAAA',
  ]) {
    check(
      rejects<FormatException>(() => base64Decode(text)),
      'invalid input $text',
    );
    check(
      rejects<FormatException>(
        () => decodeChunks(text, text.length, finalSlice: true),
      ),
      'invalid final slice $text',
    );
  }
  for (final byte in [-1, 256, 0x100000000]) {
    check(
      rejects<ArgumentError>(() => base64Encode([byte])) &&
          rejects<ArgumentError>(() => encodeChunks(base64, [byte], 0)),
      'invalid byte $byte',
    );
  }
  check(
    rejects<FormatException>(() => base64.normalize('Zg===')) &&
        rejects<FormatException>(() => base64.normalize('%')),
    'invalid normalization',
  );

  final bytes = List<int>.filled(2048, 255);
  final text = '////' * 682 + '//8=';
  check(
    encodeChunks(base64, bytes, 1, collect: true) == text,
    'encoder state survives collection',
  );
  final decoded = decodeChunks(text, 3, collect: true);
  check(
    decoded.length == bytes.length && decoded.every((byte) => byte == 255),
    'decoder state and grown output survive collection',
  );

  final failure = StateError('output failure');
  final failing = base64.encoder.startChunkedConversion(
    StringConversionSink.withCallback((_) => throw failure),
  );
  try {
    failing.addSlice([102], 0, 1, true);
    throw StateError('output failure swallowed');
  } catch (error) {
    check(identical(error, failure), 'output failure identity');
  }
  final codec = utf8.fuse(base64);
  check(codec.encode('Dart!') == 'RGFydCE=', 'codec composition');
  check(codec.decode('RGFydCE=') == 'Dart!', 'composed decode');
  check(base64.inverted.encode('Zg==').single == 102, 'inverted codec');
  check(
    await Stream<List<int>>.fromIterable([
          [102],
          [],
          [111, 111],
        ]).transform(base64.encoder).join() ==
        'Zm9v',
    'encoder stream',
  );
  final streamBytes = await Stream<String>.fromIterable(['Z', 'm9', '', 'v'])
      .transform(base64.decoder)
      .fold(<int>[], (all, chunk) => all..addAll(chunk));
  check(streamBytes.join(',') == '102,111,111', 'decoder stream');
  print('base64:ok');
}
