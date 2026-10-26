class StringBuffer {
  List<String> _parts = <String>[];
  int _length = 0;

  StringBuffer([Object content = '']) {
    this.write(content);
  }

  void write(Object? object) {
    String value = object.toString();
    if (value.isEmpty) return;
    this._parts.add(value);
    this._length = this._length + value.length;
  }

  void writeln([Object? value = '']) {
    this.write(value);
    this.write('\n');
  }

  void clear() {
    this._parts.clear();
    this._length = 0;
  }

  int get length => this._length;

  bool get isEmpty => this._length == 0;

  String toString() {
    if (this._length == 0) return '';
    if (this._parts.length == 1) return this._parts[0];
    List<int> units = List<int>.filled(this._length, 0);
    int offset = 0;
    int partIndex = 0;
    while (partIndex < this._parts.length) {
      String part = this._parts[partIndex];
      int character = 0;
      while (character < part.length) {
        units[offset] = part.codeUnitAt(character);
        offset++;
        character++;
      }
      partIndex++;
    }
    return String.fromCharCodes(units);
  }
}
