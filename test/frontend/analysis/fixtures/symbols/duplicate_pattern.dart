// ignore_for_file: equal_keys_in_map_pattern
int match(Map<Symbol, int> values) => switch (values) {
  {#_secret: final a, #_secret: final b} => a + b,
  _ => 0,
};
