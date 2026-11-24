import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

/// The standard libraries for [target], made of [files]. [environment] is what
/// programs can ask for, besides what the compiler tells them.
SdkSources sdkFor(
  Target target,
  SdkFiles files, {
  Map<String, String> environment = const {},
}) => SdkSources(
  files,
  systems: [target.system.name, target.label],
  declared: environment,
);
