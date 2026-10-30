/// Lexical token kinds, including contextual and built-in keywords.
///
/// A keyword token does not by itself prohibit use as an identifier. The parser
/// applies the rules for the syntactic position and language version.
enum TokenKind {
  /// The empty range at the end of the source.
  eof(null),

  /// An unexpected source character retained for recovery.
  invalid(null),
  identifier(null),
  integer(null),
  hexadecimalInteger(null),
  doubleLiteral(null),

  /// A complete string without interpolation, including its delimiters.
  stringLiteral(null),

  /// The opening delimiter and text before the first interpolation.
  stringStart(null),

  /// Text between interpolations, which can be empty.
  stringMiddle(null),

  /// Text after the last interpolation, including the closing delimiter.
  stringEnd(null),

  /// A dollar sign followed by an identifier or keyword token.
  interpolationIdentifier(r'$'),

  /// The opening delimiter of an interpolated expression.
  interpolationStart(r'${'),

  /// The closing brace of an interpolated expression.
  interpolationEnd('}'),

  /// A line comment, excluding its line ending.
  lineComment(null),

  /// A block comment, including nested comments and delimiters.
  blockComment(null),

  /// A script tag at offset zero, excluding its line ending.
  scriptTag(null),

  leftParen('('),
  rightParen(')'),
  leftBracket('['),
  rightBracket(']'),
  emptyBrackets('[]'),
  emptyBracketsAssign('[]='),
  leftBrace('{'),
  rightBrace('}'),
  comma(','),
  colon(':'),
  semicolon(';'),
  at('@'),
  hash('#'),
  dot('.'),
  cascade('..'),
  spread('...'),
  nullAwareSpread('...?'),
  question('?'),
  nullAwareAccess('?.'),
  nullAwareCascade('?..'),
  ifNull('??'),
  ifNullAssign('??='),
  assign('='),
  equal('=='),
  arrow('=>'),
  bang('!'),
  notEqual('!='),
  plus('+'),
  increment('++'),
  plusAssign('+='),
  minus('-'),
  decrement('--'),
  minusAssign('-='),
  star('*'),
  starAssign('*='),
  slash('/'),
  slashAssign('/='),
  percent('%'),
  percentAssign('%='),
  tilde('~'),
  truncateDivide('~/'),
  truncateDivideAssign('~/='),
  ampersand('&'),
  logicalAnd('&&'),
  andAssign('&='),
  bar('|'),
  logicalOr('||'),
  orAssign('|='),
  caret('^'),
  xorAssign('^='),
  less('<'),
  lessEqual('<='),
  shiftLeft('<<'),
  shiftLeftAssign('<<='),
  greater('>'),
  greaterEqual('>='),
  shiftRight('>>'),
  shiftRightAssign('>>='),
  unsignedShiftRight('>>>'),
  unsignedShiftRightAssign('>>>='),

  keywordAbstract('abstract', isKeyword: true),
  keywordAs('as', isKeyword: true),
  keywordAssert('assert', isKeyword: true),
  keywordAsync('async', isKeyword: true),
  keywordAwait('await', isKeyword: true),
  keywordBase('base', isKeyword: true),
  keywordBreak('break', isKeyword: true),
  keywordCase('case', isKeyword: true),
  keywordCatch('catch', isKeyword: true),
  keywordClass('class', isKeyword: true),
  keywordConst('const', isKeyword: true),
  keywordContinue('continue', isKeyword: true),
  keywordCovariant('covariant', isKeyword: true),
  keywordDefault('default', isKeyword: true),
  keywordDeferred('deferred', isKeyword: true),
  keywordDo('do', isKeyword: true),
  keywordDynamic('dynamic', isKeyword: true),
  keywordElse('else', isKeyword: true),
  keywordEnum('enum', isKeyword: true),
  keywordExport('export', isKeyword: true),
  keywordExtends('extends', isKeyword: true),
  keywordExtension('extension', isKeyword: true),
  keywordExternal('external', isKeyword: true),
  keywordFactory('factory', isKeyword: true),
  keywordFalse('false', isKeyword: true),
  keywordFinal('final', isKeyword: true),
  keywordFinally('finally', isKeyword: true),
  keywordFor('for', isKeyword: true),
  keywordFunction('Function', isKeyword: true),
  keywordGet('get', isKeyword: true),
  keywordHide('hide', isKeyword: true),
  keywordIf('if', isKeyword: true),
  keywordImplements('implements', isKeyword: true),
  keywordImport('import', isKeyword: true),
  keywordIn('in', isKeyword: true),
  keywordInterface('interface', isKeyword: true),
  keywordIs('is', isKeyword: true),
  keywordLate('late', isKeyword: true),
  keywordLibrary('library', isKeyword: true),
  keywordMixin('mixin', isKeyword: true),
  keywordNew('new', isKeyword: true),
  keywordNull('null', isKeyword: true),
  keywordOf('of', isKeyword: true),
  keywordOn('on', isKeyword: true),
  keywordOperator('operator', isKeyword: true),
  keywordPart('part', isKeyword: true),
  keywordRequired('required', isKeyword: true),
  keywordRethrow('rethrow', isKeyword: true),
  keywordReturn('return', isKeyword: true),
  keywordSealed('sealed', isKeyword: true),
  keywordSet('set', isKeyword: true),
  keywordShow('show', isKeyword: true),
  keywordStatic('static', isKeyword: true),
  keywordSuper('super', isKeyword: true),
  keywordSwitch('switch', isKeyword: true),
  keywordSync('sync', isKeyword: true),
  keywordThis('this', isKeyword: true),
  keywordThrow('throw', isKeyword: true),
  keywordTrue('true', isKeyword: true),
  keywordTry('try', isKeyword: true),
  keywordType('type', isKeyword: true),
  keywordTypedef('typedef', isKeyword: true),
  keywordVar('var', isKeyword: true),
  keywordVoid('void', isKeyword: true),
  keywordWhen('when', isKeyword: true),
  keywordWhile('while', isKeyword: true),
  keywordWith('with', isKeyword: true),
  keywordYield('yield', isKeyword: true);

  const TokenKind(this.spelling, {this.isKeyword = false});

  /// The fixed source spelling, or `null` for kinds with varying text.
  final String? spelling;

  /// Whether this kind represents a reserved, built-in, or contextual keyword.
  final bool isKeyword;
}
