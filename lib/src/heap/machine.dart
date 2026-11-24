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

  int load8(int address);
  void store8(int address, int value);

  /// 4096 bytes that are there even when no memory is left.
  int get outputBuffer;

  /// Writes [count] bytes at [address] to a file.
  void write(int file, int address, int count);

  /// Writes [value], which is finite, with [digits] significant digits, at
  /// [address], followed by a byte 0. It looks like `1.25`, `12.5` or
  /// `1.25e+30`.
  void formatDouble(double value, int digits, int address);

  /// Reads a number like [formatDouble] writes it.
  double parseDouble(int address);

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
  /// A record is the number of its references, whether it has elements that
  /// are references, and the offsets of the former.
  int get classTable;

  /// The global variables that hold references.
  int get globalRoots;
  int get globalRootCount;

  /// Where the frame of the innermost call of a C function is, or 0. The frame
  /// of the one before is 8 bytes below it.
  int get nativeFrame;

  /// Whether to collect before every allocation, to find mistakes.
  bool get collectsAlways;

  /// The number of the class of [object], and where it is.
  int classNumber(Object object);
  int addressOf(Object object);
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
int load8(int address) => machine.load8(address);
void store8(int address, int value) => machine.store8(address, value);
int outputBuffer() => machine.outputBuffer;
void write(int file, int address, int count) =>
    machine.write(file, address, count);
void formatDouble(double value, int digits, int address) =>
    machine.formatDouble(value, digits, address);
double parseDouble(int address) => machine.parseDouble(address);
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

int classNumber(Object object) => machine.classNumber(object);
int addressOf(Object object) => machine.addressOf(object);

/// Whether [a] and [b] are at the same place.
bool isSame(Object? a, Object? b) => identical(a, b);
int nativeFrame() => machine.nativeFrame;
