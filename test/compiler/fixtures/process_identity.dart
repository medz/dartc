import 'dart:convert';
import 'dart:io';

void main() {
  print(
    jsonEncode([
      pid,
      Platform.numberOfProcessors,
      Platform.localHostname,
      Platform.resolvedExecutable,
    ]),
  );
}
