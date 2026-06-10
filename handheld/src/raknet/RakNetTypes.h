#ifndef __NETWORK_TYPES_H
#define __NETWORK_TYPES_H

#include "Export.h"
#include <stdint.h>
#include <string>
#include <string.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include "RakNetTime.h"

#define BITS_TO_BYTES(x) (((x) + 7) >> 3)
#define BYTES_TO_BITS(x) ((x) << 3)

namespace RakNet {

class RakPeerInterface;
class BitStream;

typedef uint32_t BitSize_t;
typedef unsigned short SystemIndex;
typedef unsigned char MessageID;

struct uint24_t {
  uint32_t val;

  uint24_t() {}
  uint24_t(uint32_t i) { val = i; }
  operator uint32_t() const { return val; }
  uint24_t &operator=(const uint32_t &i) {
    val = i;
    return *this;
  }
};

struct RAK_DLL_EXPORT SystemAddress {
  union {
    struct sockaddr_storage sa_stor;
    struct sockaddr_in addr4;
  } address;

  SystemIndex systemIndex;
  unsigned short debugPort;

  SystemAddress() : systemIndex((SystemIndex)-1), debugPort(0) {
    address.addr4.sin_family = AF_INET;
    address.addr4.sin_port = 0;
    address.addr4.sin_addr.s_addr = 0;
  }
  SystemAddress(const char *str) : systemIndex((SystemIndex)-1), debugPort(0) {
    address.addr4.sin_family = AF_INET;
    address.addr4.sin_port = 0;
    address.addr4.sin_addr.s_addr = inet_addr(str);
  }
  SystemAddress(const char *str, unsigned short portVal) : systemIndex((SystemIndex)-1), debugPort(portVal) {
    address.addr4.sin_family = AF_INET;
    address.addr4.sin_port = htons(portVal);
    address.addr4.sin_addr.s_addr = inet_addr(str);
  }

  bool operator==(const SystemAddress &other) const {
    return address.addr4.sin_addr.s_addr == other.address.addr4.sin_addr.s_addr &&
           address.addr4.sin_port == other.address.addr4.sin_port;
  }
  bool operator!=(const SystemAddress &other) const {
    return !(*this == other);
  }
  bool operator<(const SystemAddress &other) const {
    if (address.addr4.sin_addr.s_addr == other.address.addr4.sin_addr.s_addr) {
      return address.addr4.sin_port < other.address.addr4.sin_port;
    }
    return address.addr4.sin_addr.s_addr < other.address.addr4.sin_addr.s_addr;
  }
  bool operator>(const SystemAddress &other) const {
    if (address.addr4.sin_addr.s_addr == other.address.addr4.sin_addr.s_addr) {
      return address.addr4.sin_port > other.address.addr4.sin_port;
    }
    return address.addr4.sin_addr.s_addr > other.address.addr4.sin_addr.s_addr;
  }

  unsigned short GetPort() const {
    return ntohs(address.addr4.sin_port);
  }
  void SetPort(unsigned short s) {
    address.addr4.sin_port = htons(s);
    debugPort = s;
  }
  unsigned short GetPortNetworkOrder() const {
    return address.addr4.sin_port;
  }
  void SetPortNetworkOrder(unsigned short s) {
    address.addr4.sin_port = s;
    debugPort = ntohs(s);
  }
  unsigned char GetIPVersion() const {
    return 4;
  }
  void SetBinaryAddress(const char *str, char portDelineator = ':') {
    (void)portDelineator;
    address.addr4.sin_addr.s_addr = inet_addr(str);
  }
  bool FromString(const char *str, char portDelineator = ':', int ipVersion = 4) {
    (void)ipVersion;
    if (!str) return false;
    char ip[64];
    strncpy(ip, str, sizeof(ip) - 1);
    ip[sizeof(ip) - 1] = 0;
    char *delim = strchr(ip, portDelineator);
    if (delim) {
        *delim = 0;
        SetPort(atoi(delim + 1));
    }
    address.addr4.sin_addr.s_addr = inet_addr(ip);
    return true;
  }
  bool FromStringExplicitPort(const char *str, unsigned short portVal, int ipVersion = 4) {
    (void)ipVersion;
    address.addr4.sin_addr.s_addr = inet_addr(str);
    SetPort(portVal);
    return true;
  }

  const char* ToString(bool writePort, char portDelineator = ':') const {
    static char buf[64];
    char* ipStr = inet_ntoa(address.addr4.sin_addr);
    if (writePort) {
      snprintf(buf, sizeof(buf), "%s%c%d", ipStr, portDelineator, GetPort());
    } else {
      snprintf(buf, sizeof(buf), "%s", ipStr);
    }
    return buf;
  }
  void ToString(bool writePort, char* dest, char portDelineator = ':') const {
    strcpy(dest, ToString(writePort, portDelineator));
  }
};

const SystemAddress UNASSIGNED_SYSTEM_ADDRESS;

struct RAK_DLL_EXPORT RakNetGUID {
  uint64_t g;
  SystemIndex systemIndex;

  RakNetGUID() : g(0xFFFFFFFFFFFFFFFFULL), systemIndex((SystemIndex)-1) {}
  explicit RakNetGUID(uint64_t _g) : g(_g), systemIndex((SystemIndex)-1) {}

  operator uint64_t() const { return g; }

  bool operator==(const RakNetGUID &other) const { return g == other.g; }
  bool operator!=(const RakNetGUID &other) const { return g != other.g; }
  bool operator<(const RakNetGUID &other) const { return g < other.g; }
  bool operator>(const RakNetGUID &other) const { return g > other.g; }

  const char* ToString(void) const {
    static char buf[32];
    if (g == 0xFFFFFFFFFFFFFFFFULL) return "UNASSIGNED_RAKNET_GUID";
    snprintf(buf, sizeof(buf), "%llu", g);
    return buf;
  }
  void ToString(char *dest) const {
    strcpy(dest, ToString());
  }
  bool FromString(const char *source) {
    g = strtoull(source, nullptr, 10);
    return true;
  }
  static unsigned long ToUint32(const RakNetGUID &guid) {
    return (unsigned long)((guid.g >> 32) ^ (guid.g & 0xFFFFFFFF));
  }
};

const RakNetGUID UNASSIGNED_RAKNET_GUID((uint64_t)-1);

struct RAK_DLL_EXPORT AddressOrGUID {
  RakNetGUID rakNetGuid;
  SystemAddress systemAddress;

  AddressOrGUID() {}
  AddressOrGUID(const SystemAddress &input) {
    rakNetGuid = UNASSIGNED_RAKNET_GUID;
    systemAddress = input;
  }
  AddressOrGUID(const RakNetGUID &input) {
    rakNetGuid = input;
    systemAddress = UNASSIGNED_SYSTEM_ADDRESS;
  }
  inline bool operator==(const AddressOrGUID &right) const {
    return (rakNetGuid != UNASSIGNED_RAKNET_GUID && rakNetGuid == right.rakNetGuid) ||
           (systemAddress != UNASSIGNED_SYSTEM_ADDRESS && systemAddress == right.systemAddress);
  }
};

struct RAK_DLL_EXPORT Packet {
  SystemAddress systemAddress;
  RakNetGUID guid;
  unsigned int length;
  BitSize_t bitSize;
  unsigned char *data;
  bool deleteData;
};

struct RAK_DLL_EXPORT SocketDescriptor {
  unsigned short port;
  char hostAddress[32];
  short socketFamily;
  
  SocketDescriptor() : port(0), socketFamily(2) { hostAddress[0] = 0; } // AF_INET = 2
  SocketDescriptor(unsigned short _port, const char *_hostAddress) : port(_port), socketFamily(2) {
    if (_hostAddress) {
      strncpy(hostAddress, _hostAddress, sizeof(hostAddress) - 1);
      hostAddress[sizeof(hostAddress) - 1] = 0;
    } else {
      hostAddress[0] = 0;
    }
  }
};

struct RAK_DLL_EXPORT PublicKey {
  // dummy
};

enum StartupResult {
  RAKNET_STARTED,
  RAKNET_ALREADY_STARTED,
  INVALID_SOCKET_DESCRIPTORS,
  INVALID_MAX_CONNECTIONS,
  SOCKET_FAMILY_NOT_SUPPORTED,
  SOCKET_PORT_ALREADY_IN_USE,
  SOCKET_FAILED_TO_BIND,
  SOCKET_FAILED_TEST_SEND,
  PORT_CANNOT_BE_ZERO,
  FAILED_TO_CREATE_NETWORK_THREAD,
  STARTUP_OTHER_FAILURE,
};

enum ConnectionAttemptResult {
  CONNECTION_ATTEMPT_STARTED,
  INVALID_PARAMETER,
  CANNOT_RESOLVE_DOMAIN_NAME,
  ALREADY_CONNECTED_TO_ENDPOINT,
  CONNECTION_ATTEMPT_ALREADY_IN_PROGRESS,
  SECURITY_INITIALIZATION_FAILED
};

enum ConnectionState {
  IS_PENDING,
  IS_CONNECTING,
  IS_CONNECTED,
  IS_DISCONNECTING,
  IS_SILENTLY_DISCONNECTING,
  IS_DISCONNECTED,
  IS_NOT_CONNECTED,
};

} // namespace RakNet

#endif
