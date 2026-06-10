// RakPeerRust.cpp — implements RakPeerInterface backed by the raknet-sys Rust crate.
// Replaces RakPeer.cpp, ReliabilityLayer.cpp, SocketLayer.cpp, RakNetSocket.cpp, SendToThread.cpp.
#include "RakPeerInterface.h"
#include "BitStream.h"
#include "RakNetTypes.h"
#include "Export.h"
#include "PacketPriority.h"
#include "RakNetSmartPtr.h"
#include "RakNetSocket.h"
#include <stdarg.h>
#include <string>
#include <vector>

#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <unordered_map>
#include <arpa/inet.h>

// ---- C declarations for the Rust FFI ----------------------------------------

extern "C" {

struct RakPeerHandle; // opaque

struct CPacket {
    uint8_t*  data;
    uint32_t  length;
    uint64_t  guid;
    uint8_t   system_address[46]; // null-terminated dotted-decimal IP
    uint16_t  system_port;
};

RakPeerHandle* raknet_peer_create();
void           raknet_peer_destroy(RakPeerHandle*);

uint8_t raknet_peer_startup_server(RakPeerHandle*, uint32_t max_connections, uint16_t port);
uint8_t raknet_peer_startup_client(RakPeerHandle*);
void    raknet_peer_shutdown(RakPeerHandle*, uint32_t block_ms);
bool    raknet_peer_is_active(const RakPeerHandle*);

void    raknet_peer_set_max_incoming(RakPeerHandle*, uint32_t n);
void    raknet_peer_set_timeout_time(RakPeerHandle*, uint32_t ms);
void    raknet_peer_set_occasional_ping(RakPeerHandle*, bool enabled);
void    raknet_peer_set_offline_ping_response(RakPeerHandle*, const uint8_t* data, uint32_t len);

uint64_t raknet_peer_get_my_guid(const RakPeerHandle*);

uint8_t raknet_peer_connect(RakPeerHandle*, const char* host, uint16_t port);
void    raknet_peer_ping(RakPeerHandle*, const char* host, uint16_t port, bool only_if_accepting);

bool raknet_peer_receive(RakPeerHandle* peer, uint8_t** out_data, uint32_t* out_len,
                         uint64_t* out_guid, uint16_t* out_port, uint8_t* out_ip);
void raknet_peer_deallocate_data(uint8_t* data, uint32_t len);

bool raknet_peer_send(RakPeerHandle*, const uint8_t* data, uint32_t len,
                      uint8_t priority, uint8_t reliability, uint8_t channel,
                      uint64_t guid, bool broadcast);

// GUID FFI exports
void        raknet_guid_to_string(const RakNet::RakNetGUID* guid, char* dest);
const char* raknet_guid_to_string_static(const RakNet::RakNetGUID* guid);
bool        raknet_guid_from_string(RakNet::RakNetGUID* guid, const char* source);
uint32_t    raknet_guid_to_uint32(const RakNet::RakNetGUID* guid);

// SystemAddress FFI exports
uint16_t    raknet_system_address_get_port(const RakNet::SystemAddress* addr);
void        raknet_system_address_to_string(const RakNet::SystemAddress* addr, bool write_port, char* dest, char port_delineator);
const char* raknet_system_address_to_string_static(const RakNet::SystemAddress* addr, bool write_port, char port_delineator);
bool        raknet_system_address_equals(const RakNet::SystemAddress* a, const RakNet::SystemAddress* b);

// RakString FFI exports
bool        rakstring_is_empty(const RakNet::RakString* s);
size_t      rakstring_get_length(const RakNet::RakString* s);
int         rakstring_strcmp(const RakNet::RakString* a, const RakNet::RakString* b);
bool        rakstring_equals_str(const RakNet::RakString* s, const char* str);

} // extern "C"

// ---- RakPeerRust -------------------------------------------------------------

namespace RakNet {

class RakPeerRust : public RakPeerInterface {
public:
    RakPeerRust() : _handle(raknet_peer_create()) {}
    ~RakPeerRust() override { raknet_peer_destroy(_handle); }

    // --- startup/shutdown ---

    StartupResult Startup(unsigned short maxConnections,
                          SocketDescriptor* socketDescriptors,
                          unsigned socketDescriptorCount,
                          int /*threadPriority*/ = -99999) override {
        uint8_t r;
        if (maxConnections > 1) {
            uint16_t port = socketDescriptors ? socketDescriptors[0].port : 0;
            r = raknet_peer_startup_server(_handle, maxConnections, port);
        } else {
            r = raknet_peer_startup_client(_handle);
        }
        switch (r) {
            case 0:  return RAKNET_STARTED;
            case 1:  return RAKNET_ALREADY_STARTED;
            default: return INVALID_SOCKET_DESCRIPTORS;
        }
    }

    void Shutdown(unsigned int blockDuration,
                  unsigned char /*orderingChannel*/ = 0,
                  PacketPriority /*prio*/ = LOW_PRIORITY) override {
        raknet_peer_shutdown(_handle, blockDuration);
    }

    bool IsActive(void) const override {
        return raknet_peer_is_active(_handle);
    }

    // --- connection ---

    ConnectionAttemptResult Connect(const char* host, unsigned short remotePort,
                                    const char* /*password*/, int /*passwordLength*/,
                                    PublicKey* /*publicKey*/ = 0,
                                    unsigned /*socketIndex*/ = 0,
                                    unsigned /*attempts*/ = 12,
                                    unsigned /*timeBetweenAttempts*/ = 500,
                                    RakNet::TimeMS /*timeoutTime*/ = 0) override {
        return raknet_peer_connect(_handle, host, remotePort) == 0
            ? CONNECTION_ATTEMPT_STARTED
            : CANNOT_RESOLVE_DOMAIN_NAME;
    }

    ConnectionAttemptResult ConnectWithSocket(const char*, unsigned short,
                                              const char*, int,
                                              RakNetSmartPtr<RakNetSocket>,
                                              PublicKey* = 0, unsigned = 0,
                                              unsigned = 12,
                                              RakNet::TimeMS = 0) override {
        return CANNOT_RESOLVE_DOMAIN_NAME;
    }

    void CloseConnection(const AddressOrGUID /*target*/, bool /*sendDisconnect*/,
                         unsigned char /*orderingChannel*/ = 0,
                         PacketPriority /*prio*/ = LOW_PRIORITY) override {}

    void CancelConnectionAttempt(const SystemAddress /*target*/) override {}

    ConnectionState GetConnectionState(const AddressOrGUID) override { return IS_PENDING; }

    // --- incoming connection limits ---

    void SetMaximumIncomingConnections(unsigned short n) override {
        raknet_peer_set_max_incoming(_handle, n);
    }
    unsigned short GetMaximumIncomingConnections(void) const override { return 0; }
    unsigned short NumberOfConnections(void) const override { return 0; }
    unsigned short GetMaximumNumberOfPeers(void) const override { return 0; }

    // --- configuration ---

    void SetTimeoutTime(RakNet::TimeMS timeMS, const SystemAddress /*target*/) override {
        raknet_peer_set_timeout_time(_handle, static_cast<uint32_t>(timeMS));
    }
    RakNet::TimeMS GetTimeoutTime(const SystemAddress) override { return 0; }

    void SetOccasionalPing(bool doPing) override {
        raknet_peer_set_occasional_ping(_handle, doPing);
    }

    void SetOfflinePingResponse(const char* data, const unsigned int length) override {
        raknet_peer_set_offline_ping_response(
            _handle, reinterpret_cast<const uint8_t*>(data), length);
    }
    void GetOfflinePingResponse(char** /*data*/, unsigned int* /*length*/) override {}

    void SetLimitIPConnectionFrequency(bool) override {}
    void AllowConnectionResponseIPMigration(bool) override {}
    void SetSplitMessageProgressInterval(int) override {}
    int  GetSplitMessageProgressInterval(void) const override { return 0; }
    void SetUnreliableTimeout(RakNet::TimeMS) override {}
    void SetPerConnectionOutgoingBandwidthLimit(unsigned) override {}
    int  GetMTUSize(const SystemAddress) const override { return 1400; }

    // --- ping ---

    void Ping(const SystemAddress /*target*/) override {}

    bool Ping(const char* host, unsigned short remotePort,
              bool onlyReplyOnAcceptingConnections,
              unsigned /*connectionSocketIndex*/ = 0) override {
        raknet_peer_ping(_handle, host, remotePort, onlyReplyOnAcceptingConnections);
        return true;
    }

    int GetAveragePing(const AddressOrGUID) override { return -1; }
    int GetLastPing(const AddressOrGUID) const override { return -1; }
    int GetLowestPing(const AddressOrGUID) const override { return -1; }

    // --- identity ---

    const RakNetGUID GetMyGUID(void) const override {
        RakNetGUID g;
        g.g = raknet_peer_get_my_guid(_handle);
        return g;
    }

    SystemAddress GetMyBoundAddress(const int /*socketIndex*/ = 0) override {
        return UNASSIGNED_SYSTEM_ADDRESS;
    }

    const RakNetGUID& GetGuidFromSystemAddress(const SystemAddress /*input*/) const override {
        return UNASSIGNED_RAKNET_GUID;
    }

    SystemAddress GetSystemAddressFromGuid(const RakNetGUID /*input*/) const override {
        return UNASSIGNED_SYSTEM_ADDRESS;
    }

    SystemAddress GetExternalID(const SystemAddress /*target*/) const override {
        return UNASSIGNED_SYSTEM_ADDRESS;
    }

    SystemAddress GetInternalID(const SystemAddress /*systemAddress*/ = UNASSIGNED_SYSTEM_ADDRESS,
                                const int /*index*/ = 0) const override {
        return UNASSIGNED_SYSTEM_ADDRESS;
    }

    bool GetClientPublicKeyFromSystemAddress(const SystemAddress /*input*/,
                                             char* /*output*/) const override {
        return false;
    }

    // --- send ---

    uint32_t Send(const char* data, const int length,
                  PacketPriority priority, PacketReliability reliability,
                  char orderingChannel, const AddressOrGUID systemIdentifier,
                  bool broadcast, uint32_t /*receipt*/ = 0) override {
        return raknet_peer_send(
            _handle, reinterpret_cast<const uint8_t*>(data), static_cast<uint32_t>(length),
            static_cast<uint8_t>(priority), static_cast<uint8_t>(reliability),
            static_cast<uint8_t>(orderingChannel),
            systemIdentifier.rakNetGuid.g, broadcast) ? 1 : 0;
    }

    uint32_t Send(const RakNet::BitStream* bitStream,
                  PacketPriority priority, PacketReliability reliability,
                  char orderingChannel, const AddressOrGUID systemIdentifier,
                  bool broadcast, uint32_t receipt = 0) override {
        return Send(reinterpret_cast<const char*>(bitStream->GetData()),
                    static_cast<int>(bitStream->GetNumberOfBytesUsed()),
                    priority, reliability, orderingChannel, systemIdentifier,
                    broadcast, receipt);
    }

    void SendLoopback(const char* /*data*/, const int /*length*/) override {}

    uint32_t SendList(const char** /*data*/, const int* /*lengths*/,
                      const int /*numParameters*/, PacketPriority,
                      PacketReliability, char, const AddressOrGUID,
                      bool, uint32_t = 0) override { return 0; }

    void SendTTL(const char* /*host*/, unsigned short /*remotePort*/,
                 int /*ttl*/, unsigned /*socketIndex*/ = 0) override {}

    bool SendOutOfBand(const char*, unsigned short, const char*,
                       BitSize_t, unsigned = 0) override { return false; }

    bool AdvertiseSystem(const char*, unsigned short, const char*,
                         int, unsigned = 0) override { return false; }

    // --- receive ---
 
    Packet* Receive(void) override {
        uint8_t* data = nullptr;
        uint32_t length = 0;
        uint64_t guid = 0;
        uint16_t port = 0;
        uint8_t ip[46] = {0};

        if (!raknet_peer_receive(_handle, &data, &length, &guid, &port, ip)) {
            return nullptr;
        }

        Packet* p = new Packet();
        p->data    = data;
        p->length  = length;
        p->bitSize = static_cast<BitSize_t>(length) * 8;
        p->guid.g  = guid;
        p->systemAddress.SetBinaryAddress(reinterpret_cast<const char*>(ip));
        p->systemAddress.SetPort(port);
        p->deleteData = false;
        
        _inflight[p] = data;
        return p;
    }

    void DeallocatePacket(Packet* packet) override {
        if (!packet) return;
        auto it = _inflight.find(packet);
        if (it != _inflight.end()) {
            raknet_peer_deallocate_data(it->second, packet->length);
            _inflight.erase(it);
        }
        delete packet;
    }

    Packet* AllocatePacket(unsigned dataSize) override {
        Packet* p = new Packet();
        p->data = static_cast<unsigned char*>(malloc(dataSize));
        p->length = dataSize;
        p->deleteData = true;
        return p;
    }

    void PushBackPacket(Packet* packet, bool /*pushAtHead*/) override {
        // No-op; caller manages lifecycle.
        (void)packet;
    }

    // --- system lists ---

    bool GetConnectionList(SystemAddress* /*remoteSystems*/,
                           unsigned short* /*numberOfSystems*/) const override { return false; }

    int GetIndexFromSystemAddress(const SystemAddress) const override { return -1; }
    SystemAddress GetSystemAddressFromIndex(int) override { return UNASSIGNED_SYSTEM_ADDRESS; }
    RakNetGUID    GetGUIDFromIndex(int) override { return UNASSIGNED_RAKNET_GUID; }

    void GetSystemList(DataStructures::List<SystemAddress>& /*addresses*/,
                       DataStructures::List<RakNetGUID>& /*guids*/) const override {}

    // --- address helpers ---

    unsigned GetNumberOfAddresses(void) override { return 0; }
    const char* GetLocalIP(unsigned int) override { return "127.0.0.1"; }
    bool IsLocalIP(const char*) override { return false; }

    void ChangeSystemAddress(RakNetGUID, const SystemAddress&) override {}

    // --- ban list ---

    void AddToBanList(const char*, RakNet::TimeMS = 0) override {}
    void RemoveFromBanList(const char*) override {}
    void ClearBanList(void) override {}
    bool IsBanned(const char*) override { return false; }

    // --- security ---

    bool InitializeSecurity(const char*, const char*, bool = false) override { return false; }
    void DisableSecurity(void) override {}
    void AddToSecurityExceptionList(const char*) override {}
    void RemoveFromSecurityExceptionList(const char*) override {}
    bool IsInSecurityExceptionList(const char*) override { return false; }

    // --- passwords ---

    void SetIncomingPassword(const char*, int) override {}
    void GetIncomingPassword(char*, int*) override {}

    // --- sockets ---

    RakNetSmartPtr<RakNetSocket> GetSocket(const SystemAddress) override {
        return RakNetSmartPtr<RakNetSocket>();
    }

    void GetSockets(DataStructures::List<RakNetSmartPtr<RakNetSocket>>&) override {}
    void ReleaseSockets(DataStructures::List<RakNetSmartPtr<RakNetSocket>>&) override {}

    void WriteOutOfBandHeader(RakNet::BitStream*) override {}
    void SetUserUpdateThread(void (*)(RakPeerInterface*, void*), void*) override {}

    // --- network simulator ---

    void ApplyNetworkSimulator(float, unsigned short, unsigned short) override {}
    bool IsNetworkSimulatorActive(void) override { return false; }

    // --- statistics ---

    RakNetStatistics* GetStatistics(const SystemAddress,
                                    RakNetStatistics* rns = 0) override { return rns; }
    bool GetStatistics(const int /*index*/, RakNetStatistics*) override { return false; }
    unsigned int GetReceiveBufferSize(void) override { return 0; }

    // --- misc ---

    uint32_t GetNextSendReceipt(void) override { return 0; }
    uint32_t IncrementNextSendReceipt(void) override { return 0; }

    // --- plugin system ---

    void AttachPlugin(PluginInterface2*) override {}
    void DetachPlugin(PluginInterface2*) override {}

private:
    RakPeerHandle* _handle;
    std::unordered_map<Packet*, uint8_t*> _inflight;
};

} // namespace RakNet

// Wire up GetInstance() / DestroyInstance() for RakPeerInterface.
STATIC_FACTORY_DEFINITIONS(RakNet::RakPeerInterface, RakNet::RakPeerRust)

namespace RakNet {



// ---- RakString ----

RakString::RakString(const char *format, ...) {
    va_list args;
    va_start(args, format);
    va_list args2;
    va_copy(args2, args);
    int len = vsnprintf(nullptr, 0, format, args2);
    va_end(args2);
    if (len > 0) {
        resize(len);
        va_start(args, format);
        vsnprintf(&((*this)[0]), len + 1, format, args);
        va_end(args);
    }
}

RakString::RakString(const unsigned char *format, ...) {
    va_list args;
    va_start(args, format);
    va_list args2;
    va_copy(args2, args);
    int len = vsnprintf(nullptr, 0, (const char*)format, args2);
    va_end(args2);
    if (len > 0) {
        resize(len);
        va_start(args, format);
        vsnprintf(&((*this)[0]), len + 1, (const char*)format, args);
        va_end(args);
    }
}

RakString RakString::SubStr(unsigned int index, unsigned int count) const {
    if (index >= length()) return RakString();
    return RakString(substr(index, count));
}

void RakString::Serialize(BitStream *bs) const {
    Serialize(c_str(), bs);
}

void RakString::Serialize(const char *str, BitStream *bs) {
    unsigned short l = (unsigned short)strlen(str);
    bs->Write(l);
    bs->WriteAlignedBytes((const unsigned char *)str, (const unsigned int)l);
}

void RakString::SerializeCompressed(BitStream *bs, uint8_t languageId, bool writeLanguageId) const {
    Serialize(bs);
}

void RakString::SerializeCompressed(const char *str, BitStream *bs, uint8_t languageId, bool writeLanguageId) {
    Serialize(str, bs);
}

bool RakString::Deserialize(BitStream *bs) {
    unsigned short l;
    if (!bs->Read(l)) return false;
    if (l == 0) {
        clear();
        return true;
    }
    resize(l);
    return bs->ReadAlignedBytes((unsigned char*)&((*this)[0]), l);
}

bool RakString::Deserialize(char *str, BitStream *bs) {
    unsigned short l;
    if (!bs->Read(l)) return false;
    if (l == 0) {
        str[0] = '\0';
        return true;
    }
    if (!bs->ReadAlignedBytes((unsigned char*)str, l)) {
        return false;
    }
    str[l] = '\0';
    return true;
}

bool RakString::DeserializeCompressed(BitStream *bs, bool readLanguageId) {
    return Deserialize(bs);
}

bool RakString::DeserializeCompressed(char *str, BitStream *bs, bool readLanguageId) {
    return Deserialize(str, bs);
}

} // namespace RakNet

const RakNet::RakString operator+(const RakNet::RakString &lhs, const RakNet::RakString &rhs) {
    RakNet::RakString res(lhs);
    res += rhs;
    return res;
}

