import 'dart:convert';

enum Conversion() {
  json,
  pretty,
  reviver,
  jsonChunks,
  jsonFinalSlice,
  utf8,
  malformedUtf8,
  utf8Chunks,
  malformedUtf8Chunks,
  encodeUtf8,
  fusedJson,
  fusedJsonChunks,
  customJson,
  invalidJsonObject,
  safeString,
  uriEncodeComponent,
  uriEncodeQuery,
  uriEncodeFull,
  uriDecodeComponent,
  uriDecodeQuery,
  uriDecodeFull,
  uriQuery,
}

final class Payload(final String text) {
  Object toJson() => {'text': text};
}

String conversionText(String source, Conversion mode, int split) {
  try {
    switch (mode) {
      case .json:
        return jsonEncode(jsonDecode(source));
      case .pretty:
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(source));
      case .reviver:
        final trace = <Object?>[];
        final result = jsonDecode(
          source,
          reviver: (key, value) {
            trace.add(key);
            return value is int ? value + 1 : value;
          },
        );
        return '${jsonEncode(result)}|${jsonEncode(trace)}';
      case .jsonChunks || .jsonFinalSlice:
        Object? result;
        final output = ChunkedConversionSink<Object?>.withCallback(
          (values) => result = values.single,
        );
        final input = const JsonDecoder().startChunkedConversion(output);
        input.addSlice(source, 0, split, false);
        input.addSlice(source, split, source.length, mode == .jsonFinalSlice);
        if (mode == .jsonChunks) input.close();
        return jsonEncode(result);
      case .utf8 || .malformedUtf8 || .utf8Chunks || .malformedUtf8Chunks:
        final bytes = (jsonDecode(source) as List).cast<int>();
        final decoder = Utf8Decoder(
          allowMalformed:
              mode == .malformedUtf8 || mode == .malformedUtf8Chunks,
        );
        if (mode == .utf8 || mode == .malformedUtf8) {
          return decoder.convert(bytes);
        }
        final output = StringBuffer();
        final input = decoder.startChunkedConversion(
          StringConversionSink.fromStringSink(output),
        );
        input.addSlice(bytes, 0, split, false);
        input.addSlice(bytes, split, bytes.length, false);
        input.close();
        return output.toString();
      case .encodeUtf8:
        return jsonEncode(utf8.encode(source));
      case .fusedJson || .fusedJsonChunks:
        final bytes = (jsonDecode(source) as List).cast<int>();
        final converter = utf8.decoder.fuse(json.decoder);
        if (mode == .fusedJson) return jsonEncode(converter.convert(bytes));
        Object? result;
        final input = converter.startChunkedConversion(
          ChunkedConversionSink<Object?>.withCallback(
            (values) => result = values.single,
          ),
        );
        input
          ..add(bytes.sublist(0, split))
          ..add(bytes.sublist(split))
          ..close();
        return jsonEncode(result);
      case .customJson:
        var calls = 0;
        final value = Payload(source);
        final automatic = jsonEncode(value);
        final custom = jsonEncode(
          [value, value],
          toEncodable: (object) {
            calls++;
            return (object as Payload).text;
          },
        );
        return '$automatic|$custom|$calls';
      case .invalidJsonObject:
        final cycle = <Object?>[];
        cycle.add(cycle);
        final Object value = switch (split) {
          0 => {1: source},
          1 => cycle,
          2 => double.nan,
          3 => double.infinity,
          _ => Payload(source),
        };
        return jsonEncode(value, toEncodable: (_) => throw StateError(source));
      case .safeString:
        return Error.safeToString(source);
      case .uriEncodeComponent:
        return Uri.encodeComponent(source);
      case .uriEncodeFull:
        return Uri.encodeFull.call(source);
      case .uriDecodeComponent:
        return Uri.decodeComponent.call(source);
      case .uriDecodeFull:
        return Uri.decodeFull(source);
      case .uriEncodeQuery || .uriDecodeQuery || .uriQuery:
        final encoding = switch (split) {
          1 => latin1,
          2 => ascii,
          3 => const Utf8Codec(allowMalformed: true),
          _ => utf8,
        };
        return switch (mode) {
          .uriEncodeQuery => Uri.encodeQueryComponent(
            source,
            encoding: encoding,
          ),
          .uriDecodeQuery => Uri.decodeQueryComponent(
            source,
            encoding: encoding,
          ),
          _ => jsonEncode(Uri.splitQueryString(source, encoding: encoding)),
        };
    }
  } on ArgumentError {
    return 'argument';
  } on FormatException catch (error) {
    return 'format:${error.offset}';
  } on JsonCyclicError {
    return 'cycle';
  } on JsonUnsupportedObjectError catch (error) {
    return 'unsupported:${error.cause is StateError}';
  }
}
