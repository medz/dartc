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
  latin1Decode,
  latin1DecodeInvalid,
  latin1Chunks,
  latin1InvalidChunks,
  latin1FinalSlice,
  latin1InvalidFinalSlice,
  uriObject,
  uriBuild,
  uriResolve,
  uriData,
  uriAddress,
  uriLifetime,
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
      case .latin1Decode ||
          .latin1DecodeInvalid ||
          .latin1Chunks ||
          .latin1InvalidChunks ||
          .latin1FinalSlice ||
          .latin1InvalidFinalSlice:
        final bytes = (jsonDecode(source) as List).cast<int>();
        final decoder = Latin1Decoder(
          allowInvalid:
              mode == .latin1DecodeInvalid ||
              mode == .latin1InvalidChunks ||
              mode == .latin1InvalidFinalSlice,
        );
        if (mode == .latin1Decode || mode == .latin1DecodeInvalid) {
          return decoder.convert(bytes);
        }
        String? result;
        var closes = 0;
        final input = decoder.startChunkedConversion(
          StringConversionSink.withCallback((value) {
            result = value;
            closes++;
          }),
        );
        final last =
            mode == .latin1FinalSlice || mode == .latin1InvalidFinalSlice;
        input.addSlice(bytes, 0, split, false);
        input.addSlice(bytes, split, bytes.length, last);
        if (!last) input.close();
        return '${jsonEncode(result)}|$closes';
      case .uriObject:
        final uri = switch (split) {
          1 => Uri.tryParse(source),
          2 => Uri.parse('<$source>', 1, source.length + 1),
          _ => Uri.parse(source),
        };
        if (uri == null) return 'null';
        String? origin;
        try {
          origin = uri.origin;
        } on StateError {
          origin = null;
        }
        return jsonEncode([
          uri.toString(),
          uri.scheme,
          uri.userInfo,
          uri.host,
          uri.port,
          uri.path,
          uri.query,
          uri.fragment,
          uri.hasScheme,
          uri.hasAuthority,
          uri.hasPort,
          uri.hasQuery,
          uri.hasFragment,
          uri.hasAbsolutePath,
          uri.isAbsolute,
          uri.pathSegments,
          uri.queryParametersAll,
          origin,
          uri.normalizePath().toString(),
          uri.removeFragment().toString(),
          uri == Uri.parse(uri.toString()),
          uri.hashCode == Uri.parse(uri.toString()).hashCode,
        ]);
      case .uriBuild:
        final parameters = <String, dynamic>{
          'q': ['a b', 'c+d'],
          'flag': null,
          'empty': <String>[],
        };
        final make = Uri.new;
        final uri = switch (split) {
          0 => Uri(
            scheme: 'HTTPS',
            userInfo: 'a:b',
            host: source,
            port: 443,
            pathSegments: ['a b', 'é', '..', '🙂'],
            queryParameters: parameters,
            fragment: 'f #',
          ),
          1 => make(
            scheme: 'HTTPS',
            userInfo: 'a:b',
            host: source,
            port: 443,
            pathSegments: ['a b', 'é', '..', '🙂'],
            queryParameters: parameters,
            fragment: 'f #',
          ),
          2 => Uri.http(source, '/a b/é', parameters),
          _ => Uri.https(source, '/a b/é', parameters),
        };
        (parameters['q'] as List).add('later');
        parameters.clear();
        final replace = uri.replace;
        return jsonEncode([
          uri.toString(),
          uri.pathSegments,
          uri.queryParametersAll,
          replace(
            scheme: 'http',
            port: 81,
            path: '/new/../target',
            query: '',
            fragment: '',
          ).toString(),
          uri.toString(),
        ]);
      case .uriResolve:
        final parts = (jsonDecode(source) as List).cast<String>();
        final uri = Uri.parse(parts[0]);
        final resolve = uri.resolve;
        return (split == 0
                ? resolve(parts[1])
                : uri.resolveUri(Uri.parse(parts[1])))
            .toString();
      case .uriData:
        final data = switch (split) {
          0 || 1 => Uri.dataFromString(
            source,
            encoding: utf8,
            mimeType: 'text/plain',
            parameters: {'name': 'a b'},
            base64: split == 1,
          ).data!,
          2 || 3 => UriData.fromBytes(
            utf8.encode(source),
            parameters: {'charset': 'utf-8'},
            percentEncoded: split == 2,
          ),
          4 => UriData.fromString(source),
          5 => UriData.fromUri(Uri.parse(source)),
          _ => UriData.parse(source),
        };
        String decoded;
        try {
          decoded = data.contentAsString();
        } on UnsupportedError {
          decoded = 'unsupported-charset';
        }
        return jsonEncode([
          data.toString(),
          data.uri.toString(),
          data.mimeType,
          data.charset,
          data.isMimeType('TEXT/PLAIN'),
          data.isCharset('UTF-8'),
          data.isEncoding(utf8),
          data.isBase64,
          data.contentText,
          data.contentAsBytes(),
          decoded,
          data.parameters,
        ]);
      case .uriAddress:
        return jsonEncode(switch (split) {
          0 => Uri.parseIPv4Address(source),
          1 => Uri.parseIPv4Address('<$source>', 1, source.length + 1),
          2 => Uri.parseIPv6Address(source),
          _ => Uri.parseIPv6Address('<$source>', 1, source.length + 1),
        });
      case .uriLifetime:
        final uri = Uri.parse(source);
        final segments = uri.pathSegments;
        final iterator = segments.iterator..moveNext();
        final all = uri.queryParametersAll;
        final single = uri.queryParameters;
        final resolve = uri.resolve;
        final values = {uri: 'retained'};
        final immutable = <bool>[];
        for (final mutate in <void Function()>[
          segments.clear,
          all.clear,
          all['x']!.clear,
          single.clear,
        ]) {
          try {
            mutate();
            immutable.add(false);
          } on UnsupportedError {
            immutable.add(true);
          }
        }
        for (var i = 0; i < 4000; i++) {
          final garbage = List<String>.filled(64, 'allocation:$i');
          if (garbage.length != 64) throw StateError('allocation');
        }
        return jsonEncode([
          immutable,
          iterator.current,
          iterator.moveNext(),
          iterator.current,
          all,
          single,
          values[Uri.parse(source)],
          resolve('../next').toString(),
          uri.toString(),
        ]);
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
