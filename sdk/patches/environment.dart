String _stringFromEnvironment(
  Map<String, String> values,
  String name,
  String defaultValue,
) => values[name] ?? defaultValue;

int _intFromEnvironment(
  Map<String, String> values,
  String name,
  int defaultValue,
) => int.tryParse(values[name] ?? '') ?? defaultValue;

bool _boolFromEnvironment(
  Map<String, String> values,
  String name,
  bool defaultValue,
) => switch (values[name]) {
  'true' => true,
  'false' => false,
  _ => defaultValue,
};

bool _hasEnvironment(Map<String, String> values, String name) =>
    values.containsKey(name);
