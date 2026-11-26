// What sockets are on Linux.

const _afInet6 = 10, _solSocket = 1, _soReuseAddress = 2, _soReusePort = 15;
const _soError = 4, _soBroadcast = 6, _ipv6Only = 26, _ipTtl = 2;
const _ipMulticastIf = 32, _ipMulticastTtl = 33, _ipMulticastLoop = 34;
const _ipAddMembership = 35, _ipDropMembership = 36, _ipv6MulticastIf = 17;
const _ipv6MulticastHops = 18, _ipv6MulticastLoop = 19, _ipv6JoinGroup = 20;
const _ipv6LeaveGroup = 21;
const _bytesToRead = 0x541b, _noWaitMessage = 0x40, _nonBlocking = 0x800;
const _eInProgress = 115, _eAgain = 11, _eAddressInUse = 98;
const _eAddressNotAvailable = 99;

/// What host lookups ask for, and that names have to be found.
const _lookUpFlags = 0, _nameRequired = 8;

/// Where `struct addrinfo` has the address and the next one.
const _infoAddress = 24, _infoNext = 40;

/// Starts a socket address of [family] at [address], of [length] bytes.
void _setFamily(int address, int family, int length) =>
    store16(address, family);

int _familyAt(int address) => load16(address);

/// Sockets that are made are not given to programs that are started.
void _keepFile(int file) {}

/// What [type] is for sockets that are made: one that is closed on `exec`.
int _socketType(int type) => type | 0x80000;

/// What sends give, so that writing after the peer closed does not end the
/// program, and how long the address of a Unix domain socket is.
const _sendFlags = 0x4000, _unixLength = 110;

void _setNoSignal(int socket) {}
