/// What the runtime needs of the machine it runs on.
///
/// Calls of the functions below become single operations in compiled programs.
/// Elsewhere they use [machine].
abstract interface class Machine() {
  int load64(int address);
  void store64(int address, int value);
  int load32(int address);
  int load32Signed(int address);
  void store32(int address, int value);

  /// Zeroed memory, or 0 if there is none.
  int mapMemory(int bytes);
  void unmapMemory(int address, int bytes);
  Never trap();

  /// Writes a byte to standard error.
  void writeError(int byte);

  /// Continues at [code] in the function whose frame is at [frame], which then
  /// finds the exception and its trace.
  Never resume(int frame, int code, Object exception, Object trace);

  /// The frame of the function calling.
  int get frameAddress;

  /// Where the program's code starts.
  int get codeStart;

  /// The encoded stack maps of the program's calls.
  int get stackMaps;

  /// The encoded places where calls that throw continue.
  int get handlers;

  /// A 32-bit word for each class, giving where its record is in the table.
  /// A record is the number of its references and their offsets.
  int get classTable;

  /// The global variables that hold references.
  int get globalRoots;
  int get globalRootCount;

  /// Whether to collect before every allocation, to find mistakes.
  bool get collectsAlways;
}

/// The machine that the runtime runs on outside compiled programs.
late Machine machine;

int load64(int address) => machine.load64(address);
void store64(int address, int value) => machine.store64(address, value);
int load32(int address) => machine.load32(address);
int load32Signed(int address) => machine.load32Signed(address);
void store32(int address, int value) => machine.store32(address, value);
int mapMemory(int bytes) => machine.mapMemory(bytes);
void unmapMemory(int address, int bytes) => machine.unmapMemory(address, bytes);
Never trap() => machine.trap();
void writeError(int byte) => machine.writeError(byte);
Never resume(int frame, int code, Object exception, Object trace) =>
    machine.resume(frame, code, exception, trace);
int frameAddress() => machine.frameAddress;
int codeStart() => machine.codeStart;
int stackMaps() => machine.stackMaps;
int handlers() => machine.handlers;
int classTable() => machine.classTable;
int globalRoots() => machine.globalRoots;
int globalRootCount() => machine.globalRootCount;
bool collectsAlways() => machine.collectsAlways;

/// Whether [a] and [b] are at the same place.
bool isSame(Object? a, Object? b) => identical(a, b);
