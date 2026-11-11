import '../console.dart' as console;

void Function(String)? _consoleZone;

@patch
void Function(String)? get printToZone => _consoleZone;

@patch
set printToZone(void Function(String)? value) => _consoleZone = value;

@patch
void printToConsole(String line) => console.writeLine(line);
