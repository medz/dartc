/// Writes what the official `RegExp` knows about characters, for ours.
///
/// Usage: dart run tool/unicode_properties.dart
library;

import 'dart:io';

const _propertiesTarget = 'sdk/native/core/unicode_properties.dart';
const _scriptsTarget = 'sdk/native/core/unicode_scripts.dart';

/// The general categories, by their short and long names. Those that are made
/// of others tell these.
const _categories = '''
Lu,Uppercase_Letter Ll,Lowercase_Letter Lt,Titlecase_Letter
Lm,Modifier_Letter Lo,Other_Letter Mn,Nonspacing_Mark Mc,Spacing_Mark
Me,Enclosing_Mark Nd,Decimal_Number,digit Nl,Letter_Number No,Other_Number
Pc,Connector_Punctuation Pd,Dash_Punctuation Ps,Open_Punctuation
Pe,Close_Punctuation Pi,Initial_Punctuation Pf,Final_Punctuation
Po,Other_Punctuation Sm,Math_Symbol Sc,Currency_Symbol Sk,Modifier_Symbol
So,Other_Symbol Zs,Space_Separator Zl,Line_Separator Zp,Paragraph_Separator
Cc,Control,cntrl Cf,Format Cs,Surrogate Co,Private_Use Cn,Unassigned
LC,Cased_Letter=Lu+Ll+Lt L,Letter=Lu+Ll+Lt+Lm+Lo
M,Mark,Combining_Mark=Mn+Mc+Me N,Number=Nd+Nl+No
P,Punctuation,punct=Pc+Pd+Ps+Pe+Pi+Pf+Po S,Symbol=Sm+Sc+Sk+So
Z,Separator=Zs+Zl+Zp C,Other=Cc+Cf+Cs+Co+Cn''';

const _properties = '''
ASCII_Hex_Digit,AHex Alphabetic,Alpha Any Assigned ASCII Bidi_Control,Bidi_C
Bidi_Mirrored,Bidi_M Case_Ignorable,CI Cased Changes_When_Casefolded,CWCF
Changes_When_Casemapped,CWCM Changes_When_Lowercased,CWL
Changes_When_Titlecased,CWT Changes_When_Uppercased,CWU Dash
Default_Ignorable_Code_Point,DI Deprecated,Dep Diacritic,Dia Emoji
Emoji_Component,EComp Emoji_Modifier,EMod Emoji_Modifier_Base,EBase
Emoji_Presentation,EPres Extended_Pictographic,ExtPict Extender,Ext
Grapheme_Base,Gr_Base Grapheme_Extend,Gr_Ext Hex_Digit,Hex
IDS_Binary_Operator,IDSB IDS_Trinary_Operator,IDST ID_Continue,IDC
ID_Start,IDS Ideographic,Ideo Join_Control,Join_C
Logical_Order_Exception,LOE Lowercase,Lower Math
Noncharacter_Code_Point,NChar Pattern_Syntax,Pat_Syn
Pattern_White_Space,Pat_WS Quotation_Mark,QMark Radical
Regional_Indicator,RI Sentence_Terminal,STerm Soft_Dotted,SD
Terminal_Punctuation,Term Unified_Ideograph,UIdeo Uppercase,Upper
Variation_Selector,VS White_Space,space XID_Continue,XIDC XID_Start,XIDS''';

const _scripts = '''
Adlm,Adlam Aghb,Caucasian_Albanian Ahom Arab,Arabic Armi,Imperial_Aramaic
Armn,Armenian Avst,Avestan Bali,Balinese Bamu,Bamum Bass,Bassa_Vah Batk,Batak
Beng,Bengali Berf,Beria_Erfe Bhks,Bhaiksuki Bopo,Bopomofo Brah,Brahmi
Brai,Braille Bugi,Buginese Buhd,Buhid Cakm,Chakma Cans,Canadian_Aboriginal
Cari,Carian Cham Cher,Cherokee Chrs,Chorasmian Copt,Coptic,Qaac
Cpmn,Cypro_Minoan Cprt,Cypriot Cyrl,Cyrillic Deva,Devanagari Diak,Dives_Akuru
Dogr,Dogra Dsrt,Deseret Dupl,Duployan Egyp,Egyptian_Hieroglyphs Elba,Elbasan
Elym,Elymaic Ethi,Ethiopic Gara,Garay Geor,Georgian Glag,Glagolitic
Gong,Gunjala_Gondi Gonm,Masaram_Gondi Goth,Gothic Gran,Grantha Grek,Greek
Gujr,Gujarati Gukh,Gurung_Khema Guru,Gurmukhi Hang,Hangul Hani,Han
Hano,Hanunoo Hatr,Hatran Hebr,Hebrew Hira,Hiragana
Hluw,Anatolian_Hieroglyphs Hmng,Pahawh_Hmong Hmnp,Nyiakeng_Puachue_Hmong
Hung,Old_Hungarian Ital,Old_Italic Java,Javanese Kali,Kayah_Li Kana,Katakana
Kawi Khar,Kharoshthi Khmr,Khmer Khoj,Khojki Kits,Khitan_Small_Script
Knda,Kannada Krai,Kirat_Rai Kthi,Kaithi Lana,Tai_Tham Laoo,Lao Latn,Latin
Lepc,Lepcha Limb,Limbu Lina,Linear_A Linb,Linear_B Lisu Lyci,Lycian
Lydi,Lydian Mahj,Mahajani Maka,Makasar Mand,Mandaic Mani,Manichaean
Marc,Marchen Medf,Medefaidrin Mend,Mende_Kikakui Merc,Meroitic_Cursive
Mero,Meroitic_Hieroglyphs Mlym,Malayalam Modi Mong,Mongolian Mroo,Mro
Mtei,Meetei_Mayek Mult,Multani Mymr,Myanmar Nagm,Nag_Mundari Nand,Nandinagari
Narb,Old_North_Arabian Nbat,Nabataean Newa Nkoo,Nko Nshu,Nushu Ogam,Ogham
Olck,Ol_Chiki Onao,Ol_Onal Orkh,Old_Turkic Orya,Oriya Osge,Osage Osma,Osmanya
Ougr,Old_Uyghur Palm,Palmyrene Pauc,Pau_Cin_Hau Perm,Old_Permic Phag,Phags_Pa
Phli,Inscriptional_Pahlavi Phlp,Psalter_Pahlavi Phnx,Phoenician Plrd,Miao
Prti,Inscriptional_Parthian Rjng,Rejang Rohg,Hanifi_Rohingya Runr,Runic
Samr,Samaritan Sarb,Old_South_Arabian Saur,Saurashtra Sgnw,SignWriting
Shaw,Shavian Shrd,Sharada Sidd,Siddham Sidt,Sidetic Sind,Khudawadi
Sinh,Sinhala Sogd,Sogdian Sogo,Old_Sogdian Sora,Sora_Sompeng Soyo,Soyombo
Sund,Sundanese Sunu,Sunuwar Sylo,Syloti_Nagri Syrc,Syriac Tagb,Tagbanwa
Takr,Takri Tale,Tai_Le Talu,New_Tai_Lue Taml,Tamil Tang,Tangut Tavt,Tai_Viet
Tayo,Tai_Yo Telu,Telugu Tfng,Tifinagh Tglg,Tagalog Thaa,Thaana Thai
Tibt,Tibetan Tirh,Tirhuta Tnsa,Tangsa Todr,Todhri Tols,Tolong_Siki Toto
Tutg,Tulu_Tigalari Ugar,Ugaritic Vaii,Vai Vith,Vithkuqi Wara,Warang_Citi
Wcho,Wancho Xpeo,Old_Persian Xsux,Cuneiform Yezi,Yezidi Yiii,Yi
Zanb,Zanabazar_Square Zinh,Inherited,Qaai Zyyy,Common Zzzz,Unknown''';

final _belowSurrogates = String.fromCharCodes([
  for (var i = 0; i < 0xd800; i++) i,
]);
final _aboveSurrogates = String.fromCharCodes([
  for (var i = 0xe000; i < 0x110000; i++) i,
]);

/// The first characters that the property [name] holds for, and those where
/// it ends, in order.
List<int> _rangesOf(String name) {
  final pattern = RegExp('\\p{$name}+', unicode: true);
  final result = <int>[];
  void add(int first, int end) {
    if (result.isNotEmpty && result.last == first) {
      result.last = end;
    } else {
      result.addAll([first, end]);
    }
  }

  for (final match in pattern.allMatches(_belowSurrogates)) {
    add(match.start, match.end);
  }
  for (var i = 0xd800; i < 0xe000; i++) {
    if (pattern.hasMatch(String.fromCharCode(i))) add(i, i + 1);
  }
  int character(int at) =>
      at <= 0x2000 ? 0xe000 + at : 0x10000 + ((at - 0x2000) >> 1);
  for (final match in pattern.allMatches(_aboveSurrogates)) {
    add(character(match.start), character(match.end));
  }
  return result;
}

/// [values], which grow, as the digits of their differences to base 43. Those
/// of one number but the last are 43 higher.
String _encode(List<int> values) {
  final codes = <int>[];
  var last = 0;
  for (final value in values) {
    var rest = value - last;
    last = value;
    while (rest >= 43) {
      codes.add(40 + 43 + rest % 43);
      rest ~/= 43;
    }
    codes.add(40 + rest);
  }
  return String.fromCharCodes(codes);
}

List<String> _words(String text) => text.split(RegExp(r'\s+'));

String _text(String text) => "r'$text'";

/// Where characters are told apart only by their case: the first of some, how
/// many there are, how far they are apart, and how far the one is that stands
/// for all that are the same.
List<int> _folds({required bool isUnicode}) {
  final cased = [
    for (var i = 0; i < (isUnicode ? 0x110000 : 0x10000); i++)
      if (i & 0xfff800 != 0xd800) i,
  ];
  // All of these, and what looks the same where case does not count.
  final candidates = RegExp(
    r'[\p{CWCM}\p{CWCF}\p{Lu}\p{Ll}\p{Lt}]',
    unicode: true,
  );
  final known = [
    for (final i in cased)
      if (candidates.hasMatch(String.fromCharCode(i))) i,
  ];
  final all = String.fromCharCodes(known);
  final least = <int, int>{};
  for (final i in known) {
    if (least.containsKey(i)) continue;
    final same = RegExp(
      RegExp.escape(String.fromCharCode(i)),
      caseSensitive: false,
      unicode: isUnicode,
    ).allMatches(all);
    for (final match in same) {
      least.putIfAbsent(match[0]!.runes.single, () => i);
    }
  }
  final changes = [
    for (final MapEntry(:key, :value) in least.entries)
      if (key != value) (key, value - key),
  ]..sort((a, b) => a.$1 - b.$1);
  final result = <int>[];
  for (var i = 0; i < changes.length;) {
    final (first, distance) = changes[i];
    var count = 1, step = 0;
    while (i + count < changes.length) {
      final (next, other) = changes[i + count];
      final own = next - changes[i + count - 1].$1;
      if (other != distance || own > 2 || step != 0 && own != step) break;
      step = own;
      count++;
    }
    result.addAll([first, count, step, distance]);
    i += count;
  }
  return result;
}

String _table(String name, List<int> values) {
  final lines = StringBuffer('const $name = [\n');
  var line = ' ';
  for (final value in values) {
    if (line.length + '$value'.length > 72) {
      lines.writeln('$line //');
      line = ' ';
    }
    line += ' $value,';
  }
  return '$lines$line //\n];\n';
}

void main() {
  final out = StringBuffer();
  void write(String name, List<String> lines) {
    out.writeln('const $name = [');
    for (final line in lines) {
      out.writeln('  $line,');
    }
    out.writeln('];\n');
  }

  void finish(String target) {
    File(target).writeAsStringSync('''
// What is known of characters. Made by tool/unicode_properties.dart.
//
// Sets have the first characters of ranges, and those where they end. They are
// the digits of their differences to base 43, the lowest first. Those of one
// number but the last are 43 higher.

$out''');
    out.clear();
  }

  final single = [
    for (final word in _words(_categories))
      if (!word.contains('=')) word,
  ];
  write('_categoryNames', [for (final word in single) _text(word)]);
  write('_categoryGroups', [
    for (final word in _words(_categories))
      if (word.contains('=')) _text(word),
  ]);
  write('_categorySets', [
    for (final word in single) _text(_encode(_rangesOf(word.split(',').first))),
  ]);
  final properties = _words(_properties);
  write('_propertyNames', [for (final word in properties) _text(word)]);
  write('_propertySets', [
    for (final word in properties)
      _text(_encode(_rangesOf(word.split(',').first))),
  ]);
  out
    ..writeln('''
// Characters that differ only in their case: the first of some, how many there
// are, how far they are apart, and how far the one is that stands for them.
''')
    ..writeln(_table('_folds', _folds(isUnicode: false)))
    ..write(_table('_unicodeFolds', _folds(isUnicode: true)));
  finish(_propertiesTarget);
  final scripts = _words(_scripts);
  write('_scriptNames', [for (final word in scripts) _text(word)]);
  String script(String kind, String word) =>
      _encode(_rangesOf('$kind=${word.split(',').first}'));
  write('_scriptSets', [for (final word in scripts) _text(script('sc', word))]);
  out.writeln('// With what is also used in them, if there is something.');
  write('_scriptExtensionSets', [
    for (final word in scripts)
      if (script('scx', word) case final found)
        _text(found == script('sc', word) ? '' : found),
  ]);
  finish(_scriptsTarget);
}
