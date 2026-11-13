T? maybe<T>(T value) => value;

int? Function(int) nullableResult() => maybe<int>;

int Function(int)? promoted(T Function<T>(T)? value) =>
    value == null ? null : value<int>;

int? invoke(T Function<T>(T)? value) => value?.call<int>(1);
