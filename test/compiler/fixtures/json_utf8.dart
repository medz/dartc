import 'dart:convert';

import 'core_conversion.dart' show Payload;
import 'text_conversion.dart' show Collect, check, rejects, same;

Future<void> main() async {
  final values = <Object?>[
    null,
    true,
    false,
    -9223372036854775808,
    1.25,
    -0.0,
    '',
    '\x00\n\r\t"\\',
    'π界🙂\ud800x\udc00',
    <Object?>[],
    <String, Object?>{},
    {
      'x': [null, true, 1.25],
      'y': 'π',
    },
  ];
  same(JsonUtf8Encoder().convert('🙂'), [
    34,
    240,
    159,
    153,
    130,
    34,
  ], 'fixed UTF-8 vector');
  check(
    utf8.decode(JsonUtf8Encoder().convert(values.last)) ==
        '{"x":[null,true,1.25],"y":"π"}',
    'fixed compact JSON',
  );
  for (final indent in <String?>[null, '', '  ', '\t', 'π']) {
    final text = JsonEncoder.withIndent(indent);
    final fused = text.fuse(utf8.encoder);
    for (final size in [1, 2, 3, 4, 7, 16, 256]) {
      final encoder = JsonUtf8Encoder(indent, null, size);
      final convert = encoder.convert;
      for (final value in values) {
        final expected = utf8.encode(text.convert(value));
        same(convert(value), expected, 'direct encoding and method value');
        same(fused.convert(value), expected, 'fused encoding');
        for (final wrapped in [false, true]) {
          final output = Collect<List<int>>();
          final sink = encoder.startChunkedConversion(
            wrapped ? ByteConversionSink.from(output) : output,
          );
          sink.add(value);
          check(output.closes == 1, 'add closes byte output');
          check(
            output.values.every((chunk) => chunk.length <= size),
            'chunk bound',
          );
          same(
            output.values.expand((chunk) => chunk),
            expected,
            'chunk contents',
          );
        }
      }
    }
  }

  final completedOutput = Collect<List<int>>();
  final completed = JsonUtf8Encoder().startChunkedConversion(completedOutput)
    ..add(1);
  completed
    ..close()
    ..close();
  check(completedOutput.closes == 1, 'close is idempotent after add');
  check(
    rejects<StateError>(() => completed.add(null)),
    'second object rejected',
  );

  final emptyOutput = Collect<List<int>>();
  final empty = JsonUtf8Encoder().startChunkedConversion(emptyOutput);
  empty
    ..close()
    ..close();
  check(
    emptyOutput.values.isEmpty && emptyOutput.closes == 1,
    'empty sink close',
  );
  check(rejects<StateError>(() => empty.add(1)), 'add after close');
  for (final size in [-1, 0]) {
    check(
      rejects<RangeError>(
        () => JsonUtf8Encoder(null, null, size).convert(null),
      ),
      'invalid buffer size',
    );
  }

  final payload = Payload('π');
  check(
    utf8.decode(JsonUtf8Encoder().convert(payload)) == '{"text":"π"}',
    'default toJson',
  );
  var calls = 0;
  final custom = JsonUtf8Encoder(null, (dynamic value) {
    calls++;
    return (value as Payload).text;
  }, 1);
  check(
    utf8.decode(custom.convert([payload, payload])) == '["π","π"]' &&
        calls == 2,
    'custom conversion may revisit shared objects',
  );
  final marker = Object();
  var caught = false;
  try {
    JsonUtf8Encoder(null, (_) => throw marker).convert(payload);
  } on JsonUnsupportedObjectError catch (error) {
    caught =
        identical(error.unsupportedObject, payload) &&
        identical(error.cause, marker) &&
        error.partialResult == null;
  }
  check(caught, 'conversion failure retains cause and object');
  for (final value in <Object?>[
    double.nan,
    double.infinity,
    double.negativeInfinity,
    {1: 'bad key'},
  ]) {
    check(
      rejects<JsonUnsupportedObjectError>(
        () => JsonUtf8Encoder().convert(value),
      ),
      'unencodable object',
    );
  }
  final listCycle = <Object?>[];
  listCycle.add(listCycle);
  final mapCycle = <String, Object?>{};
  mapCycle['self'] = mapCycle;
  for (final cycle in [listCycle, mapCycle]) {
    check(
      rejects<JsonCyclicError>(() => JsonUtf8Encoder().convert(cycle)),
      'cyclic object',
    );
  }

  caught = false;
  try {
    JsonUtf8Encoder()
        .startChunkedConversion(
          ByteConversionSink.withCallback((_) => throw marker),
        )
        .add(payload);
  } catch (error) {
    caught = identical(error, marker);
  }
  check(caught, 'output sink failure preserves identity');

  final retained = Collect<List<int>>();
  JsonUtf8Encoder(null, null, 3).startChunkedConversion(retained).add(values);
  for (var index = 0; index < 2000; index++) {
    final garbage = List<String>.filled(64, index.toString());
    check(garbage.first.isNotEmpty, 'allocation pressure');
  }
  same(
    retained.values.expand((chunk) => chunk),
    utf8.encode(jsonEncode(values)),
    'retained chunks survive collection',
  );

  final streamEncoder = JsonUtf8Encoder(null, null, 2);
  final chunks = await streamEncoder.bind(Stream.value(values)).toList();
  same(
    chunks.expand((chunk) => chunk),
    utf8.encode(jsonEncode(values)),
    'stream conversion',
  );
  check(
    (await streamEncoder.bind(const Stream<Object?>.empty()).toList()).isEmpty,
    'empty stream',
  );
  var produced = 0;
  Iterable<Object?> events() sync* {
    produced++;
    yield 1;
    produced++;
    yield 2;
  }

  final first = await streamEncoder
      .bind(Stream.fromIterable(events()))
      .toList();
  same(first.expand((chunk) => chunk), [49], 'stream encodes one object');
  check(produced == 1, 'closed output cancels remaining input');
  caught = false;
  try {
    await streamEncoder.bind(Stream<Object?>.error(marker)).toList();
  } catch (error) {
    caught = identical(error, marker);
  }
  check(caught, 'stream failure preserves identity');
  print('json_utf8:ok');
}
