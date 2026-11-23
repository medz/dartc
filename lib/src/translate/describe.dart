import 'package:analyzer/dart/ast/ast.dart';

/// The kind of [node] in words, from its class name.
String describe(AstNode node) => node.runtimeType
    .toString()
    .replaceFirst('Impl', '')
    .replaceAllMapped(
      RegExp('(?<!^)[A-Z]'),
      (match) => ' ${match[0]!.toLowerCase()}',
    )
    .toLowerCase();
