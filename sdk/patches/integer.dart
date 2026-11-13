@patch
class int {
  @patch
  int get bitLength {
    var value = this < 0 ? ~this : this;
    var bits = 0;
    while (value != 0) {
      value >>= 1;
      bits++;
    }
    return bits;
  }
}
