// Unicode White_Space and the BOM accepted by Dart's numeric parsers.
bool unicodeWhitespace(int unit) =>
    unit >= 9 && unit <= 13 ||
    unit == 32 ||
    unit == 133 ||
    unit == 160 ||
    unit == 5760 ||
    unit >= 8192 && unit <= 8202 ||
    unit == 8232 ||
    unit == 8233 ||
    unit == 8239 ||
    unit == 8287 ||
    unit == 12288 ||
    unit == 65279;
