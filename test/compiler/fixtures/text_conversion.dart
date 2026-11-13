import 'dart:convert';

final class Collect<T>() implements Sink<T> {
  final values = <T>[];
  int closes = 0;
  @override
  void add(T value) => values.add(value);
  @override
  void close() => closes++;
}

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

void same(Iterable<Object?> actual, Iterable<Object?> expected, String label) {
  final a = actual.toList(), b = expected.toList();
  check(a.length == b.length, label);
  for (var i = 0; i < a.length; i++) {
    check(a[i] == b[i], label);
  }
}

Future<void> main() async {
  for (final (codec, limit) in [(ascii, 127), (latin1, 255)]) {
    final bytes = List.generate(limit + 1, (i) => i);
    final source = String.fromCharCodes(bytes);
    same(codec.encode(source), bytes, 'byte alphabet encoding');
    check(codec.decode(bytes) == source, 'byte alphabet decoding');
    for (final split in {0, 1, limit ~/ 2, limit, limit + 1}) {
      final output = Collect<List<int>>();
      final input =
          codec.encoder.startChunkedConversion(output) as StringConversionSink;
      input.addSlice(source, 0, split, false);
      input.addSlice(source, split, source.length, true);
      same(output.values.expand((part) => part), bytes, 'chunked encoding');
      check(output.closes == 1, 'encoder final slice');
    }
    for (final bad in [String.fromCharCode(limit + 1), '\ud800', '\u{1f642}']) {
      check(
        rejects<ArgumentError>(() => codec.encode(bad)),
        'invalid character',
      );
      final input = codec.encoder.startChunkedConversion(Collect<List<int>>());
      check(rejects<ArgumentError>(() => input.add(bad)), 'invalid chunk');
    }
    final empty = Collect<List<int>>();
    (codec.encoder.startChunkedConversion(empty) as StringConversionSink)
        .addSlice('', 0, 0, true);
    check(
      empty.values.expand((part) => part).isEmpty && empty.closes == 1,
      'empty encoder final slice',
    );
    final streamed = await codec.encoder
        .bind(
          Stream.fromIterable([source.substring(0, 1), source.substring(1)]),
        )
        .toList();
    same(streamed.expand((part) => part), bytes, 'stream encoding');
  }
  same(const AsciiEncoder().convert('\u0100A\u0100', 1, 2), [
    65,
  ], 'ASCII slice');
  same(const Latin1Encoder().convert('\u0100\u00ff\u0100', 1, 2), [
    255,
  ], 'Latin-1 slice');
  check(
    rejects<RangeError>(() => const AsciiEncoder().convert('a', -1)),
    'encoder range',
  );
  check(
    rejects<RangeError>(() => const Latin1Encoder().convert('a', 0, 2)),
    'encoder end',
  );

  final invalid = [-1, 0, 65, 127, 128, 256, 0x100000000];
  const replaced = '\ufffd\u0000A\u007f\ufffd\ufffd\ufffd';
  check(rejects<FormatException>(() => ascii.decode(invalid)), 'strict ASCII');
  check(
    const AsciiDecoder(allowInvalid: true).convert(invalid) == replaced,
    'ASCII replacements',
  );
  for (var split = 0; split <= invalid.length; split++) {
    final strict = const AsciiDecoder().startChunkedConversion(
      Collect<String>(),
    );
    check(
      rejects<FormatException>(() {
        strict.addSlice(invalid, 0, split, false);
        strict.addSlice(invalid, split, invalid.length, true);
      }),
      'strict ASCII chunk validation',
    );
    final output = Collect<String>();
    final input = const AsciiDecoder(allowInvalid: true)
        .startChunkedConversion(output);
    input.addSlice(invalid, 0, split, false);
    input.addSlice(invalid, split, invalid.length, true);
    check(
      output.values.join() == replaced && output.closes == 1,
      'ASCII final replacement slice',
    );
  }
  for (final bytes in <List<int>>[
    [],
    [0, 65, 127],
  ]) {
    for (var split = 0; split <= bytes.length; split++) {
      final output = Collect<String>();
      final input = const AsciiDecoder().startChunkedConversion(output);
      input.addSlice(bytes, 0, split, false);
      input.addSlice(bytes, split, bytes.length, true);
      check(
        output.values.join() == String.fromCharCodes(bytes),
        'strict ASCII chunks',
      );
      check(output.closes == 1, 'strict ASCII close');
    }
  }
  check(
    await ascii.decoder
            .bind(
              Stream.fromIterable([
                [65],
                [66],
              ]),
            )
            .join() ==
        'AB',
    'ASCII stream decoding',
  );

  const tail = '\u{1f642}\ud800';
  const raw = '<>&"\'/$tail';
  for (final (mode, escaped) in [
    (HtmlEscapeMode.unknown, '&lt;&gt;&amp;&quot;&#39;&#47;'),
    (HtmlEscapeMode.element, '&lt;&gt;&amp;"\'/'),
    (HtmlEscapeMode.attribute, '&lt;&gt;&amp;&quot;\'/'),
    (HtmlEscapeMode.sqAttribute, '&lt;&gt;&amp;"&#39;/'),
    (const HtmlEscapeMode(escapeSlash: true), '<>&amp;"\'&#47;'),
  ]) {
    final escape = HtmlEscape(mode);
    final expected = '$escaped$tail';
    check(escape.convert(raw) == expected, 'HTML mode');
    for (var split = 0; split <= raw.length; split++) {
      final output = Collect<String>();
      final input = escape.startChunkedConversion(output);
      final padded = '!$raw?';
      input.addSlice(padded, 1, split + 1, false);
      input.addSlice(padded, split + 1, raw.length + 1, true);
      check(
        output.values.join() == expected && output.closes == 1,
        'HTML final slice',
      );
    }
  }
  check(htmlEscape.convert('plain') == 'plain', 'unchanged HTML');
  check(
    await htmlEscape.bind(Stream.fromIterable(['<', '&', '>'])).join() ==
        '&lt;&amp;&gt;',
    'HTML stream',
  );
  final htmlInput = htmlEscape.startChunkedConversion(Collect<String>());
  check(
    rejects<RangeError>(() => htmlInput.addSlice('a', -1, 1, false)),
    'HTML range',
  );
  check(
    rejects<RangeError>(() => htmlInput.addSlice('&', 0, 2, false)),
    'HTML end',
  );

  for (final (source, expected) in <(String, List<String>)>[
    ('', []),
    ('\n', ['']),
    ('\r\n', ['']),
    ('\n\n', ['', '']),
    ('a\r\nb\rc\nlast', ['a', 'b', 'c', 'last']),
    ('a\u2028b', ['a\u2028b']),
  ]) {
    same(const LineSplitter().convert(source), expected, 'whole lines');
    same(
      LineSplitter.split('!$source?', 1, source.length + 1),
      expected,
      'lazy line slice',
    );
    for (var split = 0; split <= source.length; split++) {
      final output = Collect<String>();
      final input = const LineSplitter().startChunkedConversion(output);
      input.addSlice(source, 0, split, false);
      input.addSlice('', 0, 0, false);
      input.addSlice(source, split, source.length, true);
      same(output.values, expected, 'split CR/LF lines');
      check(output.closes == 1, 'line final slice');
    }
  }
  final output = Collect<String>();
  final line = const LineSplitter().startChunkedConversion(output);
  for (var i = 0; i < 32; i++) {
    line.add('x');
    if (i == 3) {
      var total = 0;
      for (var j = 0; j < 4000; j++) {
        total += List<int>.filled(16, j).first;
      }
      check(total == 7998000, 'allocation loop');
    }
  }
  line.close();
  same(output.values, ['x' * 32], 'multi-chunk carry survives collection');
  check(output.closes == 1, 'explicit line close');
  same(
    await Stream.fromIterable(['a\r', '', '\nb\n', 'last'])
        .transform(const LineSplitter())
        .toList(),
    ['a', 'b', 'last'],
    'line stream',
  );
  check(rejects<RangeError>(() => LineSplitter.split('a', 2)), 'line range');

  final failure = Object();
  var caught = false;
  try {
    htmlEscape
        .startChunkedConversion(
          StringConversionSink.withCallback((_) => throw failure),
        )
        .addSlice('&', 0, 1, true);
  } catch (error) {
    caught = identical(error, failure);
  }
  check(caught, 'sink exception identity');
  caught = false;
  try {
    await Stream<String>.error(failure)
        .transform(const LineSplitter())
        .toList();
  } catch (error) {
    caught = identical(error, failure);
  }
  check(caught, 'stream exception identity');
  print('text_conversion:ok');
}
