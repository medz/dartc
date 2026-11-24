// What the constructors that ask the environment give where they are not
// constant. What is in [_environment] comes from the compiler.

String _stringFromEnvironment(String name, String defaultValue) =>
    _environment[name] ?? defaultValue;

int _intFromEnvironment(String name, int defaultValue) =>
    int.tryParse(_environment[name] ?? '') ?? defaultValue;

bool _boolFromEnvironment(String name, bool defaultValue) =>
    switch (_environment[name]) {
      'true' => true,
      'false' => false,
      _ => defaultValue,
    };

bool _boolHasEnvironment(String name) => _environment.containsKey(name);
