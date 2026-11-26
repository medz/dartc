// What sockets are on macOS.

const _afInet6 = 30, _solSocket = 0xffff, _soReuseAddress = 0x4;
const _soReusePort = 0x200, _soError = 0x1007, _soBroadcast = 0x20;
const _ipv6Only = 27, _ipTtl = 4, _ipMulticastIf = 9, _ipMulticastTtl = 10;
const _ipMulticastLoop = 11, _ipAddMembership = 12, _ipDropMembership = 13;
const _ipv6MulticastIf = 9, _ipv6MulticastHops = 10, _ipv6MulticastLoop = 11;
const _ipv6JoinGroup = 12, _ipv6LeaveGroup = 13;
const _bytesToRead = 0x4004667f, _noWaitMessage = 0x80, _nonBlocking = 0x4;
const _eInProgress = 36, _eAgain = 35, _eAddressInUse = 48;
const _eAddressNotAvailable = 49;

/// What host lookups ask for, and that names have to be found.
const _lookUpFlags = 0x400, _nameRequired = 4;

/// Where `struct addrinfo` has the address and the next one.
const _infoAddress = 32, _infoNext = 40;

/// Starts a socket address of [family] at [address], of [length] bytes.
void _setFamily(int address, int family, int length) {
  store8(address, length);
  store8(address + 1, family);
}

int _familyAt(int address) => load8(address + 1);

/// Makes [file] not be given to programs that are started.
void _keepFile(int file) => _controlFile(file, 2, 1);

/// What [type] is for sockets that are made.
int _socketType(int type) => type;

/// What sends give, and how long the address of a Unix domain socket is.
const _sendFlags = 0, _unixLength = 106;

/// Makes writing to [socket] after its peer closed not end the program.
void _setNoSignal(int socket) => _setInteger(socket, _solSocket, 0x1022, 1);
