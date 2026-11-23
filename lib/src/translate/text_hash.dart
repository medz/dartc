/// What the official runtime's `hashCode` of a string of [units] is, as
/// `_StringBase` in `sdk/native` computes it when programs run.
int hashOfText(List<int> units) {
  const mask = 0xffffffff;
  var hash = 0;
  for (final unit in units) {
    hash = (hash + unit) & mask;
    hash = (hash + (hash << 10)) & mask;
    hash ^= hash >> 6;
  }
  hash = (hash + (hash << 3)) & mask;
  hash ^= hash >> 11;
  hash = (hash + (hash << 15)) & mask;
  hash &= (1 << 30) - 1;
  return hash == 0 ? 1 : hash;
}
