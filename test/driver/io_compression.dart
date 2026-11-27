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
  final stored = List<int>.generate(2 * 65536 + 17, (i) => i * i ~/ 7 & 0xff);
  final repeated = utf8.encode('abc' * 500);
  final members = [
    ...GZipCodec(level: 0).encode(stored),
    ...gzip.encode(repeated),
  ];
  final joined = inPieces(gzip.decoder, members, 4093);
  print('stored members ${joined.length} ${hash(joined) == hash([...stored, ...repeated])}');
  final small = [1, 2, 3, 1, 2, 3, 1, 2, 3];
  final twoGzip = [...gzip.encode([1]), ...gzip.encode([2])];
  final twoZlib = [...zlib.encode([1]), ...zlib.encode([2])];
  attempt('two gzip with concatenation', () => gzip.decode(twoGzip));
  attempt('two gzip without concatenation', () => zlib.decode(twoGzip));
  attempt('two zlib with concatenation', () => gzip.decode(twoZlib));
  attempt('dictionary after a member', () =>
      ZLibDecoder(gzip: true, dictionary: dictionary).convert([
        ...zlib.encode([1]),
        ...ZLibEncoder(dictionary: dictionary).convert([2]),
      ]));
  final raw = ZLibEncoder(raw: true);
  final twoRaw = [...raw.convert([1]), ...raw.convert([2])];
  attempt('two raw with concatenation', () =>
      ZLibDecoder(raw: true, gzip: true).convert(twoRaw));
  final gzipSmall = gzip.encode(small);
  final header = [
    0x1f, 0x8b, 8, 0x1e, 0, 0, 0, 0, 0, 255,
    7, 0, 65, 66, 3, 0, 1, 2, 3,
    ...List<int>.filled(32768, 0x78), 0,
    ...List<int>.filled(348, 0x79), 0,
  ];
  // The low 16 bits of the CRC-32 of the header, split between input chunks.
  final withHeader = [...header, 0xb6, 0xf2, ...gzipSmall.skip(10)];
  attempt('chunked gzip with optional fields', () => inPieces(gzip.decoder, withHeader, 263));
  withHeader[header.length] ^= 1;
  attempt('bad gzip header checksum', () => gzip.decode(withHeader));
  final threeAs = gzip.encode([65, 65, 65]);
  final orphanMatch = [
    ...threeAs.take(10),
    // A match before any literal in this member.
    0x03, 0x02, 0,
    ...threeAs.skip(threeAs.length - 8),
  ];
  attempt('gzip member without its own history', () =>
      gzip.decode([...gzip.encode([65]), ...orphanMatch]));
  attempt('rest', () => gzip.decode([...gzip.encode([1]), 7, 8]));
  attempt('zlib rest', () => zlib.decode([...zlib.encode([1]), 7, 8]));
  attempt('cut', () => gzip.decode(gzip.encode(small).sublist(0, 12)));
  attempt('empty', () => gzip.decode([]));
  attempt('zlib of gzip', () => zlib.decode(gzip.encode(small)));
  attempt('bad', () => zlib.decode([1, 2, 3, 4]));
  final badCheck = gzip.encode(small);
  badCheck[badCheck.length - 8] ^= 1;
  attempt('bad check', () => gzip.decode(badCheck.sublist(0, badCheck.length - 4)));
  attempt('bad adler', () => zlib.decode(zlib.encode(small)..last ^= 1));
  attempt('bad data', () => zlib.decode([0x78, 0x9c, 0x07, 0, 0]));
  attempt('no dictionary', () =>
      ZLibDecoder().convert(ZLibEncoder(dictionary: [1, 2]).convert(small)));
  attempt('small window', () =>
      ZLibDecoder(windowBits: 9).convert(zlib.encode(small)));
  attempt('level', () => ZLibCodec(level: 10));
  attempt('strategy', () => ZLibCodec(strategy: 9));
  attempt('raw deflate level', () => RawZLibFilter.deflateFilter(level: 10));
  for (final (name, draining, data) in [
    ('deflate', RawZLibFilter.deflateFilter(), small),
    ('inflate', RawZLibFilter.inflateFilter(), zlib.encode(small)),
  ]) {
    draining.process(data, 0, data.length);
    if (draining.processed(flush: false) == null) throw StateError('No output');
    attempt('$name before drained', () => draining.process([], 0, 0));
    while (draining.processed(flush: false) != null) {}
    attempt('$name after drained', () => draining.process([], 0, 0));
  }
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
  var x = 7;
  final data = <int>[];
  // The incompressible prefix makes the small token buffer choose stored blocks.
  for (var i = 0; i < 1024; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    data.add(x >> 8 & 0xff);
  }
  data.addAll(payload(20000));
  print(base64.encode(data));
  codecs().forEach((name, codec) {
    final (encoder, _) = codec;
    print('$name = ${base64.encode(encoder.convert(data))}');
  });
  final withoutDictionary = ZLibEncoder(dictionary: []).convert(data);
  print('empty dictionary = ${base64.encode(withoutDictionary)}');
}
''';

/// Checks how much history is available and when input bytes are copied.
const decoderReviewProgram = r'''
import 'dart:convert';
import 'dart:io';

void attempt(String name, Object? Function() run) {
  try { print('$name: ${run()}'); } catch (e) { print('$name: $e'); }
}

void main() {
  final prefix = List<int>.generate(300, (i) => i & 255);
  // A stored block followed by a fixed-code match of length 3 at distance 300.
  final data = [0, 44, 1, 211, 254, ...prefix, 3, 134, 21, 0];
  final gzipOfExpected = gzip.encode([...prefix, 0, 1, 2]);
  final wrapped = [
    ...gzipOfExpected.take(10), ...data,
    ...gzipOfExpected.skip(gzipOfExpected.length - 8),
  ];
  final raw = ZLibDecoder(raw: true, windowBits: 8);
  attempt('raw in current output', () => raw.convert(data).sublist(300));
  attempt('gzip in current output', () =>
      ZLibDecoder(windowBits: 8).convert(wrapped).sublist(300));
  attempt('raw outside retained history', () {
    final sink = raw.startChunkedConversion(ByteConversionSink.withCallback((_) {}));
    sink.addSlice(data, 0, 305, false);
    sink.addSlice(data, 305, data.length, true);
    return 'accepted';
  });

  final dictionary = [65, 66, 67];
  final bytes = ZLibEncoder(dictionary: dictionary).convert(dictionary);
  final filter = RawZLibFilter.inflateFilter(dictionary: dictionary);
  dictionary[0] = 90;
  filter.process(bytes, 0, bytes.length);
  attempt('dictionary snapshot', filter.processed);

  // Neither block defines a distance code. Only the first needs one.
  const match = [13, 192, 129, 8, 0, 0, 0, 0, 32, 127, 235, 47];
  const literal = [5, 192, 129, 8, 0, 0, 0, 0, 32, 182, 253, 165, 78];
  attempt('match with no distance codes', () => raw.convert(match));
  attempt('literal with no distance codes', () => raw.convert(literal));
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

/// Exercises the encoder's input ownership and direct filter output.
const encoderReviewProgram = r'''
import 'dart:io';
import 'dart:typed_data';

void drain(RawZLibFilter filter, BytesBuilder output, {bool end = false}) {
  while (true) {
    final chunk = filter.processed(flush: false, end: end);
    if (chunk == null) return;
    if (chunk.length > 65536) throw StateError('output chunk exceeds 64 KiB');
    output.add(chunk);
  }
}

bool same(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) return false;
  }
  return true;
}

void main() {
  final input = [0, 1, 2, 0];
  final gzipFilter = RawZLibFilter.deflateFilter(gzip: true);
  final output = BytesBuilder(copy: false);
  gzipFilter.process(input, 1, 3);
  input[1] = 9;
  drain(gzipFilter, output, end: true);
  print('input snapshot: ${same(gzip.decode(output.takeBytes()), [1, 2])}');

  final dictionary = [65, 66, 67];
  final withDictionary = RawZLibFilter.deflateFilter(dictionary: dictionary);
  dictionary[0] = 90;
  withDictionary.process([65, 66, 67], 0, 3);
  drain(withDictionary, output, end: true);
  final decoder = ZLibDecoder(dictionary: [65, 66, 67]);
  print('dictionary snapshot: ${same(decoder.convert(output.takeBytes()), [65, 66, 67])}');

  final data = Uint8List(2 * 65536 + 17);
  for (var i = 0; i < data.length; i++) data[i] = i;
  final split = RawZLibFilter.deflateFilter(level: 0);
  const first = 32767, limit = first + 32507;
  split.process(data, 0, first);
  drain(split, output);
  split.process(data, first, limit);
  drain(split, output);
  drain(split, output, end: true);
  print('chunked stored blocks: ${same(zlib.decode(output.takeBytes()), data.sublist(0, limit))}');

  final large = RawZLibFilter.deflateFilter(level: 0);
  large.process(data, 0, data.length);
  drain(large, output, end: true);
  print('bounded output: ${same(zlib.decode(output.takeBytes()), data)}');
}
''';
