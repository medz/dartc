import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import 'calls.dart';
import 'functions.dart';

Map<String, List<LinkInput>> sharedLibraries(Target target) {
  final caller = callModules(target).first;
  final choice = target.nativeSymbol('dartc_shared_choice');
  final inputs = <LinkInput>[
    .object(caller),
    .object(
      ObjectModule(target, [
        Section.readOnlyData([1]),
        Section.data(Uint8List(256), alignment: 128),
      ], []),
    ),
  ];
  return {
    for (final (name, value) in [('shared_first', 11), ('shared_second', 42)])
      name: [
        .object(functions(target, {'dartc_shared_choice': value})),
      ],
    'shared_calls': [
      ...inputs,
      dependency(target, 'shared_first', {}),
      dependency(target, 'shared_second', {caller.imports.single: choice}),
    ],
    'missing_dependency': [
      ...inputs,
      dependency(target, 'absent_library', {}),
      dependency(target, 'shared_second', {caller.imports.single: choice}),
    ],
    'missing_symbol': [
      ...inputs,
      dependency(target, 'shared_second', {
        caller.imports.single: target.nativeSymbol('dartc_absent_symbol'),
      }),
    ],
    'missing_unused_symbol': [
      .object(ObjectModule(target, [], [], imports: ['unused'])),
      dependency(target, 'shared_second', {
        'unused': target.nativeSymbol('dartc_absent_symbol'),
      }),
    ],
  };
}

SharedLibraryInput dependency(
  Target target,
  String name,
  Map<String, String> symbols,
) => SharedLibraryInput(
  target.operatingSystem == .macos
      ? '@loader_path/$name.dylib'
      : '\$ORIGIN/$name.so',
  symbols: symbols,
);
