@patch
double _parseDouble(String source, int start, int end) =>
    double.parse(source.substring(start, end));
