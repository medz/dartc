class ConstantData {
  int type;
  // Native typeKind values; payloads are scalar words, string IDs or getter IDs.
  List<int> kinds;
  List<int> values;

  ConstantData(this.type, this.kinds, this.values);
}

List<ConstantData> constantData = <ConstantData>[];
