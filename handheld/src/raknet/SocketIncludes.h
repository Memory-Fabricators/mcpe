// All this crap just to include type SOCKET

#if defined(_WIN32)
typedef int socklen_t;
// IP_DONTFRAGMENT is different between winsock 1 and winsock 2.  Therefore,
// Winsock2.h must be linked againt Ws2_32.lib winsock.h must be linked against
// WSock32.lib.  If these two are mixed up the flag won't work correctly
#include <winsock2.h>
#else
#define closesocket close
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#define INVALID_SOCKET -1
// #include "RakMemoryOverride.h"
/// Unix/Linux uses ints for sockets
typedef int SOCKET;
#endif
