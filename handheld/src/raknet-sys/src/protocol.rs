use crate::buffer::Buffer;
/// RakNet protocol implementation.
/// Reference: vendor/rak-rs and the original RakNet 4.036 source.
///
/// Offline packet IDs (pre-connection):
///   0x01 = ID_UNCONNECTED_PING
///   0x1c = ID_UNCONNECTED_PONG
///   0x05 = ID_OPEN_CONNECTION_REQUEST_1
///   0x06 = ID_OPEN_CONNECTION_REPLY_1
///   0x07 = ID_OPEN_CONNECTION_REQUEST_2
///   0x08 = ID_OPEN_CONNECTION_REPLY_2
///   0x09 = ID_CONNECTION_REQUEST          (first online packet, inside frame)
///   0x10 = ID_CONNECTION_REQUEST_ACCEPTED (synthetic, used internally)
///   0x11 = ID_CONNECTION_ATTEMPT_FAILED   (synthetic)
///   0x13 = ID_NEW_INCOMING_CONNECTION     (synthetic)
///   0x19 = ID_INCOMPATIBLE_PROTOCOL_VERSION
use std::net::SocketAddr;

// ---- Public packet ID constants used by peer.rs -----------------------------

pub const ID_CONNECTION_REQUEST_ACCEPTED: u8 = 0x10;
pub const ID_CONNECTION_ATTEMPT_FAILED: u8 = 0x11;
pub const ID_NEW_INCOMING_CONNECTION: u8 = 0x13;

// ---- RakNet offline magic bytes (same across all versions) ------------------

const MAGIC: [u8; 16] = [
    0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78,
];

#[cfg(feature = "legacy_protocol")]
const PROTOCOL_VERSION: u8 = 5;
#[cfg(not(feature = "legacy_protocol"))]
const PROTOCOL_VERSION: u8 = 10;

const MTU: u16 = 1400;

/// Returns true if the datagram is an offline (pre-connection) packet.
pub fn is_offline(data: &[u8]) -> bool {
    match data.first() {
        Some(0x01) | Some(0x1c) | Some(0x05) | Some(0x06) | Some(0x07) | Some(0x08)
        | Some(0x19) => true,
        _ => false,
    }
}

// ---- Unconnected ping -------------------------------------------------------

pub fn build_unconnected_ping(guid: u64) -> Buffer<64> {
    let now = timestamp();
    let mut buf = Buffer::new();
    buf.push(0x01); // ID_UNCONNECTED_PING
    buf.push_slice(&now.to_be_bytes());
    buf.push_slice(&MAGIC);
    buf.push_slice(&guid.to_be_bytes());
    buf
}

// ---- Offline handler (server side) ------------------------------------------

pub struct OfflineHandler {
    my_guid: u64,
    /// Tracks peers that have completed the handshake.
    pub connected: [Option<(SocketAddr, u64)>; 64],
    /// Peers that just finished handshake this tick.
    pub just_connected_queue: [Option<SocketAddr>; 64],
}

impl OfflineHandler {
    pub fn new(guid: u64) -> Self {
        Self {
            my_guid: guid,
            connected: [None; 64],
            just_connected_queue: [None; 64],
        }
    }

    /// Process an offline datagram. Returns an optional response to send back.
    pub fn handle(
        &mut self,
        data: &[u8],
        src: SocketAddr,
        ping_resp: &[u8],
    ) -> Option<Buffer<512>> {
        let id = *data.first()?;
        match id {
            0x01 => self.handle_ping(data, src, ping_resp),
            0x05 => self.handle_ocr1(data, src),
            0x07 => self.handle_ocr2(data, src),
            _ => None,
        }
    }

    fn handle_ping(&self, data: &[u8], _src: SocketAddr, ping_resp: &[u8]) -> Option<Buffer<512>> {
        // ID_UNCONNECTED_PING: [id(1), time(8), magic(16), guid(8)]
        if data.len() < 25 {
            return None;
        }
        let time = u64::from_be_bytes(data[1..9].try_into().ok()?);
        // ID_UNCONNECTED_PONG: [id(1), time(8), server_guid(8), magic(16), data_len(2), data]
        let mut resp = Buffer::new();
        resp.push(0x1c);
        resp.push_slice(&time.to_be_bytes());
        resp.push_slice(&self.my_guid.to_be_bytes());
        resp.push_slice(&MAGIC);
        resp.push_slice(&(ping_resp.len() as u16).to_be_bytes());
        resp.push_slice(ping_resp);
        Some(resp)
    }

    fn handle_ocr1(&self, data: &[u8], _src: SocketAddr) -> Option<Buffer<512>> {
        // ID_OPEN_CONNECTION_REQUEST_1: [id(1), magic(16), protocol(1), mtu_padding(...)]
        if data.len() < 18 {
            return None;
        }
        if &data[1..17] != &MAGIC {
            return None;
        }
        let client_protocol = data[17];
        if client_protocol != PROTOCOL_VERSION {
            // ID_INCOMPATIBLE_PROTOCOL_VERSION
            let mut resp = Buffer::new();
            resp.push(0x19);
            resp.push(PROTOCOL_VERSION);
            resp.push_slice(&MAGIC);
            resp.push_slice(&self.my_guid.to_be_bytes());
            return Some(resp);
        }
        // Infer MTU from datagram size (RakNet pads to MTU with zeros).
        let mtu = data.len() as u16 + 28; // +28 for UDP+IP overhead
        // ID_OPEN_CONNECTION_REPLY_1: [id(1), magic(16), guid(8), use_security(1), mtu(2)]
        let mut resp = Buffer::new();
        resp.push(0x06);
        resp.push_slice(&MAGIC);
        resp.push_slice(&self.my_guid.to_be_bytes());
        resp.push(0); // no security
        resp.push_slice(&mtu.to_be_bytes());
        Some(resp)
    }

    fn handle_ocr2(&mut self, data: &[u8], src: SocketAddr) -> Option<Buffer<512>> {
        // ID_OPEN_CONNECTION_REQUEST_2: [id(1), magic(16), server_addr(varies), mtu(2), guid(8)]
        if data.len() < 34 {
            return None;
        }
        if &data[1..17] != &MAGIC {
            return None;
        }
        // Parse client guid (last 8 bytes).
        let client_guid = u64::from_be_bytes(data[data.len() - 8..].try_into().ok()?);
        let mtu = u16::from_be_bytes(data[data.len() - 10..data.len() - 8].try_into().ok()?);

        // Find an empty slot or update existing
        let mut found = false;
        for slot in self.connected.iter_mut() {
            if let Some((addr, _)) = slot {
                if *addr == src {
                    *slot = Some((src, client_guid));
                    found = true;
                    break;
                }
            }
        }
        if !found {
            for slot in self.connected.iter_mut() {
                if slot.is_none() {
                    *slot = Some((src, client_guid));
                    break;
                }
            }
        }

        // Add to just connected queue
        for slot in self.just_connected_queue.iter_mut() {
            if slot.is_none() {
                *slot = Some(src);
                break;
            }
        }

        // ID_OPEN_CONNECTION_REPLY_2: [id(1), magic(16), server_guid(8), client_addr(varies), mtu(2), use_security(1)]
        let addr_bytes = encode_address(src);
        let mut resp = Buffer::new();
        resp.push(0x08);
        resp.push_slice(&MAGIC);
        resp.push_slice(&self.my_guid.to_be_bytes());
        resp.push_slice(addr_bytes.as_slice());
        resp.push_slice(&mtu.to_be_bytes());
        resp.push(0); // no security
        Some(resp)
    }

    /// Returns true (and consumes the flag) if `src` just completed the handshake.
    pub fn just_connected(&mut self, src: SocketAddr) -> bool {
        for slot in self.just_connected_queue.iter_mut() {
            if let Some(addr) = slot {
                if *addr == src {
                    *slot = None;
                    return true;
                }
            }
        }
        false
    }

    pub fn guid_for(&self, src: SocketAddr) -> Option<u64> {
        for slot in self.connected.iter() {
            if let Some((addr, guid)) = slot {
                if *addr == src {
                    return Some(*guid);
                }
            }
        }
        None
    }
}

// ---- Client handshake state machine -----------------------------------------

#[allow(dead_code)]
pub enum HandshakeResult {
    Pending,
    Continue(Buffer<512>),
    Connected(u64),
    Failed,
}

pub struct ClientHandshake {
    my_guid: u64,
    state: HandshakeState,
}

#[allow(dead_code)]
enum HandshakeState {
    SendOCR1,
    WaitOCR1Reply { mtu: u16 },
    SendOCR2 { mtu: u16, server_addr: SocketAddr },
    WaitOCR2Reply,
    Done,
}

impl ClientHandshake {
    pub fn new(guid: u64) -> Self {
        Self {
            my_guid: guid,
            state: HandshakeState::SendOCR1,
        }
    }

    /// Returns the next packet we should send, if any.
    pub fn next_outgoing(&self) -> Option<Buffer<1500>> {
        match &self.state {
            HandshakeState::SendOCR1 => {
                // ID_OPEN_CONNECTION_REQUEST_1: pad to MTU - 28 bytes
                let padding = MTU as usize - 28 - 18; // 18 = id(1)+magic(16)+protocol(1)
                let mut buf = Buffer::new();
                buf.push(0x05);
                buf.push_slice(&MAGIC);
                buf.push(PROTOCOL_VERSION);
                buf.fill(0, padding);
                Some(buf)
            }
            HandshakeState::SendOCR2 { mtu, server_addr } => {
                // ID_OPEN_CONNECTION_REQUEST_2: [id(1), magic(16), server_addr(varies), mtu(2), guid(8)]
                let addr_bytes = encode_address(*server_addr);
                let mut buf = Buffer::new();
                buf.push(0x07);
                buf.push_slice(&MAGIC);
                buf.push_slice(addr_bytes.as_slice());
                buf.push_slice(&mtu.to_be_bytes());
                buf.push_slice(&self.my_guid.to_be_bytes());
                Some(buf)
            }
            _ => None,
        }
    }

    /// Process a server reply. Returns what action to take.
    pub fn handle(&mut self, data: &[u8]) -> HandshakeResult {
        let id = match data.first() {
            Some(&v) => v,
            None => return HandshakeResult::Pending,
        };
        match (&self.state, id) {
            (HandshakeState::SendOCR1, 0x06) => {
                // ID_OPEN_CONNECTION_REPLY_1: [id(1), magic(16), guid(8), security(1), mtu(2)]
                if data.len() < 28 {
                    return HandshakeResult::Pending;
                }
                if &data[1..17] != &MAGIC {
                    return HandshakeResult::Failed;
                }
                let mtu = u16::from_be_bytes([data[26], data[27]]);
                self.state = HandshakeState::WaitOCR1Reply { mtu };
                HandshakeResult::Pending
            }
            (HandshakeState::SendOCR2 { .. }, 0x08) | (HandshakeState::WaitOCR2Reply, 0x08) => {
                // ID_OPEN_CONNECTION_REPLY_2: [id(1), magic(16), server_guid(8), ...]
                if data.len() < 26 {
                    return HandshakeResult::Pending;
                }
                if &data[1..17] != &MAGIC {
                    return HandshakeResult::Failed;
                }
                let server_guid = u64::from_be_bytes(data[17..25].try_into().unwrap_or([0; 8]));
                self.state = HandshakeState::Done;
                HandshakeResult::Connected(server_guid)
            }
            (_, 0x19) => HandshakeResult::Failed, // incompatible protocol
            _ => HandshakeResult::Pending,
        }
    }

    /// Called by the outer loop once we have OCR1 reply mtu + the actual server addr.
    pub fn advance_to_ocr2(&mut self, server_addr: SocketAddr) {
        if let HandshakeState::WaitOCR1Reply { mtu } = self.state {
            self.state = HandshakeState::SendOCR2 { mtu, server_addr };
        }
    }
}

// ---- Reliability layer (minimal) --------------------------------------------
// Implements enough of RakNet's framing to exchange user packets.
// Full ACK/NACK/retransmit can be layered in later.

pub struct Frame {
    payload: Buffer<2048>,
    ack: Option<Buffer<64>>,
}

impl Frame {
    pub fn ack_payload(&self) -> Option<&[u8]> {
        self.ack.as_ref().map(|b| b.as_slice())
    }
    pub fn user_data(self) -> Option<Buffer<2048>> {
        if self.payload.is_empty() {
            None
        } else {
            Some(self.payload)
        }
    }
}

pub struct ReliabilityLayer {
    recv_seq: u32,
    send_seq: u32,
}

impl ReliabilityLayer {
    pub fn new() -> Self {
        Self {
            recv_seq: 0,
            send_seq: 0,
        }
    }

    /// Parse an incoming RakNet datagram, return frames to process.
    pub fn receive(&mut self, data: &[u8]) -> Vec<Frame> {
        let mut frames = Vec::new();
        if data.is_empty() {
            return frames;
        }

        let flags = data[0];
        let is_ack = (flags & 0xC0) == 0xC0;
        let is_nack = (flags & 0xA0) == 0xA0;

        if is_ack || is_nack {
            // ACK/NACK — nothing to surface to game code yet.
            return frames;
        }

        // Regular datagram: [flags(1), bitlen(2), seq(3), encapsulated...]
        if data.len() < 6 {
            return frames;
        }
        let seq = u24_le(&data[3..6]);
        // Build ACK response.
        let ack = build_ack(seq);
        self.recv_seq = seq.wrapping_add(1);

        // Parse encapsulated packets starting at offset 6.
        let mut pos = 6;
        while pos < data.len() {
            // Encapsulated header: [flags(1), bit_length(2)]
            if pos + 3 > data.len() {
                break;
            }
            let enc_flags = data[pos];
            let bit_len = u16::from_be_bytes([data[pos + 1], data[pos + 2]]) as usize;
            let byte_len = (bit_len + 7) / 8;
            pos += 3;

            let reliability = (enc_flags >> 5) & 0x07;
            // Reliable packets have a 3-byte reliable message number.
            if reliability >= 2 {
                pos += 3;
            }
            // Ordered packets have 3-byte order index + 1-byte channel.
            if reliability == 3 || reliability == 7 {
                pos += 4;
            }

            if pos + byte_len > data.len() {
                break;
            }
            let mut payload = Buffer::new();
            let limit = byte_len.min(2048);
            payload.push_slice(&data[pos..pos + limit]);
            pos += byte_len;

            frames.push(Frame {
                payload,
                ack: Some(ack.clone()),
            });
            // Only attach ACK to first frame to avoid duplicates.
        }

        // If no encapsulated packets parsed but we got a datagram, still ack.
        if frames.is_empty() {
            frames.push(Frame {
                payload: Buffer::new(),
                ack: Some(ack),
            });
        }
        frames
    }

    /// Wrap user data in a RakNet reliable-ordered datagram.
    pub fn send(&mut self, data: &[u8]) -> Buffer<2048> {
        let seq = self.send_seq;
        self.send_seq = self.send_seq.wrapping_add(1);

        let bit_len = (data.len() as u16) * 8;
        // flags: datagram=1, packet_pair=0, continuous_send=0, needs_b_and_as=0
        let flags: u8 = 0x84;
        // encapsulated flags: reliability=ReliableOrdered(3), not split
        let enc_flags: u8 = 3 << 5;

        let mut buf = Buffer::new();
        buf.push(flags);
        buf.push_slice(&bit_len.to_be_bytes()); // bit length of payload section
        buf.push_slice(&u24_le_bytes(seq));
        // Encapsulated packet header:
        buf.push(enc_flags);
        buf.push_slice(&bit_len.to_be_bytes());
        // Reliable message number (3 bytes LE):
        buf.push_slice(&u24_le_bytes(seq));
        // Order index (3 bytes) + channel (1 byte):
        buf.push_slice(&u24_le_bytes(seq));
        buf.push(0); // channel 0
        buf.push_slice(data);

        buf
    }
}

// ---- Address encoding -------------------------------------------------------

fn encode_address(addr: SocketAddr) -> Buffer<32> {
    let mut buf = Buffer::new();
    match addr {
        SocketAddr::V4(a) => {
            buf.push(4); // AF_INET marker
            buf.push_slice(&a.ip().octets());
            buf.push_slice(&a.port().to_be_bytes());
        }
        SocketAddr::V6(a) => {
            buf.push(6); // AF_INET6 marker
            buf.push_slice(&a.ip().octets());
            buf.push_slice(&a.port().to_be_bytes());
        }
    }
    buf
}

// ---- Misc helpers -----------------------------------------------------------

fn timestamp() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn u24_le(bytes: &[u8]) -> u32 {
    (bytes[0] as u32) | ((bytes[1] as u32) << 8) | ((bytes[2] as u32) << 16)
}

fn u24_le_bytes(v: u32) -> [u8; 3] {
    [
        (v & 0xff) as u8,
        ((v >> 8) & 0xff) as u8,
        ((v >> 16) & 0xff) as u8,
    ]
}

fn build_ack(seq: u32) -> Buffer<64> {
    // ACK datagram: [flags(1)=0xC0, count(2)=1, max_equals_min(1)=1, seq(3)]
    let mut buf = Buffer::new();
    buf.push(0xC0);
    buf.push_slice(&1u16.to_be_bytes());
    buf.push(1); // max_equals_min = true
    buf.push_slice(&u24_le_bytes(seq));
    buf
}
