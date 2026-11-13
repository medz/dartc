class C {
  T method<T>(T value) => value;
}

void unused(C? receiver) {
  receiver?.method<int>;
}
