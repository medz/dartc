import '../console.dart' as console;

@patch
void printToConsole(String line) => console.writeLine(line);
