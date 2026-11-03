bool compareAsObject(int n) => (n as Object) < 0;

extension on Object {
  bool operator <(int other) => true;
}
