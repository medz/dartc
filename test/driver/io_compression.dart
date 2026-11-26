/// Programs that compress and decompress.
library;

import 'dart:convert';
import 'dart:io';

/// What the programs below start with: data to compress, and how to tell it.
const _common = r'''
import 'dart:convert';
import 'dart:io';

List<int> payload(int n) {
  var x = 7;
  final words = ['alpha', 'beta', 'gamma', 'delta', ' ', '\n', 'zlib'];
  final out = <int>[];
  while (out.length < n) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    if (x % 5 == 0) {
      out.add(x >> 8 & 0xff);
    } else {
      out.addAll(utf8.encode(words[x % words.length]));
    }
  }
  return out;
}

int hash(List<int> bytes) {
  var h = 0;
  for (final b in bytes) h = (h * 31 + b) & 0xffffffff;
  return h;
}

final dictionary = utf8.encode('alpha beta gamma delta');

/// Encoders and decoders that go together, by name.
Map<String, (Converter<List<int>, List<int>>, Converter<List<int>, List<int>>)>
    codecs() => {
  for (var level = -1; level <= 9; level++)
    'zlib $level': (ZLibEncoder(level: level), ZLibDecoder()),
  'gzip': (gzip.encoder, gzip.decoder),
  'gzip 1': (GZipCodec(level: 1).encoder, gzip.decoder),
  'gzip 9': (GZipCodec(level: 9).encoder, gzip.decoder),
  'raw': (ZLibEncoder(raw: true), ZLibDecoder(raw: true)),
  for (var strategy = 0; strategy <= 4; strategy++)
    'strategy $strategy': (ZLibEncoder(strategy: strategy), ZLibDecoder()),
  for (final bits in [8, 9, 12])
    'window $bits': (ZLibEncoder(windowBits: bits), ZLibDecoder()),
  for (final level in [1, 9])
    'memory $level': (ZLibEncoder(memLevel: level), ZLibDecoder()),
  'dictionary': (
    ZLibEncoder(dictionary: dictionary),
    ZLibDecoder(dictionary: dictionary),
  ),
  'raw, which ignores dictionaries': (
    ZLibEncoder(raw: true, dictionary: dictionary),
    ZLibDecoder(raw: true, dictionary: dictionary),
  ),
};
''';

/// Compresses and decompresses in many ways, gets errors, and decompresses
/// what is given, which the official `dart` compressed.
const compressionProgram =
    _common +
    r'''
const lots = 20000;

void attempt(String name, Object? Function() work) {
  try { print('$name: ${work()}'); } catch (e) { print('$name fails: $e'); }
}

/// [data] in pieces of [size], through [converter].
List<int> inPieces(Converter<List<int>, List<int>> converter, List<int> data,
    int size) {
  final out = <int>[];
  final sink = converter.startChunkedConversion(
    ByteConversionSink.withCallback(out.addAll),
  );
  for (var at = 0; at < data.length; at += size) {
    sink.add(data.sublist(at, at + size < data.length ? at + size : data.length));
  }
  sink.close();
  return out;
}

Future<void> main() async {
  final data = payload(lots);
  codecs().forEach((name, codec) {
    final (encoder, decoder) = codec;
    final back = decoder.convert(encoder.convert(data));
    final pieces = inPieces(decoder, inPieces(encoder, data, 777), 333);
    print('$name ${back.length} ${hash(back) == hash(data)} '
        '${hash(pieces) == hash(data)}');
  });
  final streamed = await Stream.fromIterable([data, data.sublist(5)])
      .transform(gzip.encoder)
      .transform(gzip.decoder)
      .fold(0, (sum, piece) => sum + piece.length);
  print('streamed $streamed');
  final small = [1, 2, 3, 1, 2, 3, 1, 2, 3];
  attempt('two', () => gzip.decode([...gzip.encode([1]), ...gzip.encode([2])]));
  attempt('rest', () => gzip.decode([...gzip.encode([1]), 7, 8]));
  attempt('zlib rest', () => zlib.decode([...zlib.encode([1]), 7, 8]));
  attempt('cut', () => gzip.decode(gzip.encode(small).sublist(0, 12)));
  attempt('empty', () => gzip.decode([]));
  attempt('zlib of gzip', () => zlib.decode(gzip.encode(small)));
  attempt('bad', () => zlib.decode([1, 2, 3, 4]));
  attempt('bad check', () => gzip.decode(gzip.encode(small)..[14] ^= 1));
  attempt('bad adler', () => zlib.decode(zlib.encode(small)..last ^= 1));
  attempt('bad data', () => zlib.decode([0x78, 0x9c, 0x07, 0, 0]));
  attempt('no dictionary', () =>
      ZLibDecoder().convert(ZLibEncoder(dictionary: [1, 2]).convert(small)));
  attempt('small window', () =>
      ZLibDecoder(windowBits: 9).convert(zlib.encode(small)));
  attempt('level', () => ZLibCodec(level: 10));
  attempt('strategy', () => ZLibCodec(strategy: 9));
  final filter = RawZLibFilter.inflateFilter();
  filter.process([1, 2, 3], 0, 3);
  attempt('filter', () => filter.processed());
  attempt('filter again', () => filter.processed());
  final deflate = RawZLibFilter.deflateFilter();
  deflate.process(small, 0, small.length);
  attempt('unfinished', () => deflate.process(small, 0, 1));
  for (final line in await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList()) {
    final [name, text] = line.split(' = ');
    final (_, decoder) = codecs()[name]!;
    final back = decoder.convert(base64.decode(text));
    print('given $name ${back.length} ${hash(back)}');
  }
}
''';

/// Prints, for each way, what the data compresses to.
const compressedProgram =
    _common +
    r'''
void main() {
  final data = payload(20000);
  print(base64.encode(data));
  codecs().forEach((name, codec) {
    final (encoder, _) = codec;
    print('$name = ${base64.encode(encoder.convert(data))}');
  });
}
''';

final _dictionary = utf8.encode('alpha beta gamma delta');

/// Decoders of the official runtime for the names of the programs above.
Converter<List<int>, List<int>> officialDecoder(String name) => switch (name) {
  'gzip' || 'gzip 1' || 'gzip 9' => gzip.decoder,
  'raw' => ZLibDecoder(raw: true),
  'dictionary' => ZLibDecoder(dictionary: _dictionary),
  'raw, which ignores dictionaries' => ZLibDecoder(
    raw: true,
    dictionary: _dictionary,
  ),
  _ => ZLibDecoder(),
};

/// What the official runtime compresses [data] to, in the ways of the programs
/// above, as their input.
String officialInput(List<int> data) => [
  for (var level = -1; level <= 9; level += 5)
    'zlib $level = ${base64.encode(ZLibEncoder(level: level).convert(data))}',
  'gzip = ${base64.encode(gzip.encode(data))}',
  'raw = ${base64.encode(ZLibEncoder(raw: true).convert(data))}',
  for (var strategy = 1; strategy <= 4; strategy++)
    'strategy $strategy = '
        '${base64.encode(ZLibEncoder(strategy: strategy).convert(data))}',
  'window 9 = ${base64.encode(ZLibEncoder(windowBits: 9).convert(data))}',
  'dictionary = '
      '${base64.encode(ZLibEncoder(dictionary: _dictionary).convert(data))}',
].join('\n');
