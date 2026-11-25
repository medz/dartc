void main() {
  try {
    ((throw 'boom') && true) is bool;
  } catch (e) {
    print(e); // expect: boom
  }
}
