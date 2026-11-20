typedef ReadValue = int Function();

class RetainedValue {
  RetainedValue(this.value);
  final int value;
  int read() => value;
}

ReadValue recurse(int value, bool again) {
  if (again) return recurse(value, again);
  return RetainedValue(value).read;
}

ReadValue forward(int value, bool again) => recurse(value, again);
ReadValue left(int value, bool again) => forward(value, again);
ReadValue right(int value, bool again) => forward(value, again);
Never thrown(int value, bool again) => throw forward(value, again);
int use(int value, bool again) => forward(value, again)();

ReadValue? saved;
void publish(int value, bool again) {
  saved ??= forward(value, again);
}

int useSaved() => saved?.call() ?? -1;
