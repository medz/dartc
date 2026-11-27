/// Lowering of the Dart-level representation to the machine level.
library;

export 'src/lower/dispatch.dart' show dispatchSymbol;
export 'src/lower/lower.dart' show entrySymbol, functionSymbols, lowerProgram;
export 'src/lower/statics.dart' show classTableSymbol, typeTestsPrefix;
