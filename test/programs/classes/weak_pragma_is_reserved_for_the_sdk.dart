class Holder {
  @pragma('dartc:weak')
  Object? target; // error 11: Not supported yet: the dartc:weak pragma outside the SDK.
}

void main() {
  Holder();
}
