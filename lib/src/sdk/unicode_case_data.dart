import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const unicodeCaseSource = 'sdk/patches/unicode_case_data.dart';
const unicodeCaseInputs = {
  'sdk/patches/unicode/UnicodeData.txt':
      '2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c',
  'sdk/patches/unicode/SpecialCasing.txt':
      'efc25faf19de21b92c1194c111c932e03d2a5eaf18194e33f1156e96de4c9588',
  'sdk/patches/unicode/DerivedCoreProperties.txt':
      '24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08',
  'sdk/patches/unicode/LICENSE':
      'fe5c62b543e287981db198f2acfa0ca732d12591a1024536dc8fd85dacd77104',
};

/// Materializes pinned Unicode mappings as ordinary target Dart constants.
Uint8List unicodeCaseData(Uint8List Function(String) read) {
  final inputs = <String, String>{};
  for (final MapEntry(:key, :value) in unicodeCaseInputs.entries) {
    final bytes = read(key);
    if (sha256.convert(bytes).toString() != value) {
      throw FormatException('Unicode 17.0.0 data does not match its pin: $key');
    }
    inputs[key.split('/').last] = utf8.decode(bytes);
  }
  final lower = <int, List<int>>{}, upper = <int, List<int>>{};
  List<int> codes(String text) => [
    for (final value in text.trim().split(' '))
      if (value.isNotEmpty) int.parse(value, radix: 16),
  ];
  for (final line in const LineSplitter().convert(inputs['UnicodeData.txt']!)) {
    if (line.isEmpty) continue;
    final fields = line.split(';');
    final code = int.parse(fields[0], radix: 16);
    if (fields[13].isNotEmpty) lower[code] = codes(fields[13]);
    if (fields[12].isNotEmpty) upper[code] = codes(fields[12]);
  }
  for (final line in const LineSplitter().convert(
    inputs['SpecialCasing.txt']!,
  )) {
    final text = line.split('#').first.trim();
    if (text.isEmpty) continue;
    final fields = text.split(';').map((value) => value.trim()).toList();
    // Final_Sigma is the only language-neutral condition; the Dart leaf handles it.
    if (fields[4].isNotEmpty) continue;
    final code = int.parse(fields[0], radix: 16);
    lower[code] = codes(fields[1]);
    upper[code] = codes(fields[3]);
  }
  final properties = {'Cased': <int>{}, 'Case_Ignorable': <int>{}};
  for (final line in const LineSplitter().convert(
    inputs['DerivedCoreProperties.txt']!,
  )) {
    final text = line.split('#').first.trim();
    if (text.isEmpty) continue;
    final fields = text.split(';').map((value) => value.trim()).toList();
    final property = properties[fields[1]];
    if (property == null) continue;
    final range = fields[0].split('..');
    final start = int.parse(range.first, radix: 16);
    final end = int.parse(range.last, radix: 16);
    for (var code = start; code <= end; code++) {
      property.add(code);
    }
  }
  final output = StringBuffer(
    '// Unicode 17.0.0. Generated from pinned inputs; see unicode/LICENSE.\n',
  );
  for (final (name, values) in [('lower', lower), ('upper', upper)]) {
    output.writeln('const $name = <int, String>{');
    for (final code in values.keys.toList()..sort()) {
      final mapped = values[code]!;
      if (mapped.length == 1 && mapped.single == code) continue;
      output.write("$code: '");
      for (final rune in mapped) {
        output.write(r'\u{');
        output.write(rune.toRadixString(16));
        output.write('}');
      }
      output.writeln("',");
    }
    output.writeln('};');
  }
  for (final (name, property) in [
    ('cased', 'Cased'),
    ('ignored', 'Case_Ignorable'),
  ]) {
    output.writeln('const $name = <int>{');
    for (final code in properties[property]!.toList()..sort()) {
      output.writeln('$code,');
    }
    output.writeln('};');
  }
  return Uint8List.fromList(utf8.encode(output.toString()))
      .asUnmodifiableView();
}
