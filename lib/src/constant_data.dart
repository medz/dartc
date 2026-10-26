class ListConstantData {
  int type;
  // Native typeKind values; payloads are scalar words, string IDs or getter IDs.
  List<int> kinds;
  List<int> values;

  ListConstantData(this.type, this.kinds, this.values);
}

List<ListConstantData> constantLists = <ListConstantData>[];
