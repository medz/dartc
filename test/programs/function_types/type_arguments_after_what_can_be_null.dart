class C {
  C get child => this;
  T m<T>(T x) => x;
}

void show(C? c) => print(c?.child.m<int>); // error 26: What gets type arguments here can be null.

void main() => show(C());
