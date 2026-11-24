import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'constant_table.dart';

/// What the runtime has for programs.
final class RuntimeLinks(
  final SourceProgram _program,
  final LibraryElement _core,
  final HirClass Function(InterfaceElement element) _createdClass,
  final ConstantTable _constants,
) {
  final _exhaustions = <String, HirFunction>{};
  HirConstObject? _trace;

  /// Functions made here.
  Iterable<HirFunction> get functions => _exhaustions.values;

  /// Whether [library] is part of the runtime, which does not check the stack.
  static bool isRuntime(LibraryElement library) =>
      '${library.uri}'.startsWith('dart:_heap');

  /// What the runtime calls the operation that calling [element] stands for.
  static String? operationOf(ExecutableElement element) =>
      switch ('${element.library.uri}') {
        'dart:_heap/machine.dart' ||
        'dart:_heap/objects.dart' => element.displayName,
        _ => null,
      };

  LibraryElement library(String uri) => _program.sdk
      .firstWhere((library) => '${library.element.uri}' == uri)
      .element;

  Iterable<LibraryElement> get _heap =>
      _program.sdk.map((library) => library.element).where(isRuntime);

  LibraryElement get async => library('dart:async');

  /// What lets work be done later.
  MethodElement get scheduler =>
      async.getClass('_AsyncRun')!.getMethod('_scheduleImmediate')!;

  /// The function type called [name], privately so in one of some libraries.
  FunctionType functionType(String name) =>
      (async.getTypeAlias('_$name') ??
                  library('dart:ffi').getTypeAlias('_$name'))!
              .aliasedType
          as FunctionType;

  /// The function called [name], or privately so in one of some libraries.
  TopLevelFunctionElement function(String name) =>
      _core.getTopLevelFunction('_$name') ??
      const ['async', 'typed_data', 'ffi']
          .map((uri) => library('dart:$uri').getTopLevelFunction('_$name'))
          .nonNulls
          .firstOrNull ??
      _heap
          .map((library) => library.getTopLevelFunction(name))
          .nonNulls
          .firstOrNull ??
      (throw StateError('No runtime with $name.'));

  ClassElement heapClass(String name) =>
      _heap.map((library) => library.getClass(name)).nonNulls.first;

  /// A function that throws a constant of the class called [name], as nothing
  /// more can be created then.
  HirFunction exhaustion(String name) => _exhaustions[name] ??= () {
    final target = _createdClass(_core.getClass(name)!);
    final block = HirBlock();
    final object = block.add(
      HirStatic(
        HirConstObject(target, {
          for (final field in target.fields) field: null,
        }),
      ),
    );
    block.end(HirThrow(object, block.add(trace)));
    return HirFunction('throw $name', const [], null, false)..define([block]);
  }();

  /// The stack trace of what is thrown, which is empty yet.
  HirInstruction get trace {
    final class_ = _createdClass(_core.getClass('_StringStackTrace')!);
    return HirStatic(
      _trace ??= HirConstObject(class_, {
        class_.fields.single: _constants.text(''),
      }),
    );
  }
}
