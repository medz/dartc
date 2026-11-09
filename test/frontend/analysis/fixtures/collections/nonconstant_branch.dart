// ignore_for_file: non_constant_list_element, dead_code
int runtimeValue() => 7;

const values = [if (true) 1 else runtimeValue()];
