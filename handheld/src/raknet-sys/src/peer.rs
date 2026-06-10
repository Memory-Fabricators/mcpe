use std::{
    net::{SocketAddr, UdpSocket},
    sync::Arc,
    thread,
    time::{Duration, Instant},
};

use crate::buffer::{Buffer, Ring};
use crate::protocol::{self, OfflineHandler, ReliabilityLayer};

/// Protocol version in the RakNet open-connection handshake.
#[cfg(feature = "legacy_protocol")]
#[allow(dead_code)]
pub const RAKNET_PROTOCOL_VERSION: u8 = 5;
#[cfg(not(feature = "legacy_protocol"))]
#[allow(dead_code)]
pub const RAKNET_PROTOCOL_VERSION: u8 = 10;

const RECV_TIMEOUT: Duration = Duration::from_millis(10);

// RawPacket represents a parsed incoming or outgoing datagram packet.

// ---- messages between the game thread and the background I/O thread ----------

enum Command {
    ConnectClient {
        host: [u8; 128],
        host_len: usize,
        port: u16,
    },
    Send {
        data: Buffer<2048>,
        guid: u64,
        broadcast: bool,
    },
    SetPingResponse(Buffer<256>),
    Shutdown,
}

pub(crate) struct RawPacket {
    pub(crate) data: Buffer<2048>,
    pub(crate) guid: u64,
    pub(crate) addr: SocketAddr,
}

// ---- peer state --------------------------------------------------------------

enum Mode {
    Idle,
    Active {
        cmd_ring: Arc<Ring<Command, 64>>,
        pkt_ring: Arc<Ring<RawPacket, 64>>,
        _thread: thread::JoinHandle<()>,
        my_guid: u64,
    },
}

pub struct RakPeer {
    mode: Mode,
    offline_ping_resp: Buffer<256>,
    pub error_state: i32,
}

impl RakPeer {
    pub fn new() -> Self {
        Self {
            mode: Mode::Idle,
            offline_ping_resp: Buffer::new(),
            error_state: 0,
        }
    }

    /// Returns 0 = RAKNET_STARTED, 1 = ALREADY_STARTED, 2 = FAILED.
    pub fn startup_server(&mut self, max_connections: u32, port: u16) -> u8 {
        if matches!(self.mode, Mode::Active { .. }) {
            return 1;
        }
        let bind_addr = format!("0.0.0.0:{port}");
        let socket = match UdpSocket::bind(&bind_addr) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[raknet-sys] bind {bind_addr}: {e}");
                return 2;
            }
        };
        socket.set_read_timeout(Some(RECV_TIMEOUT)).ok();

        let my_guid = rand_guid();
        let ping_resp = self.offline_ping_resp.clone();
        let cmd_ring = Arc::new(Ring::<Command, 64>::new());
        let pkt_ring = Arc::new(Ring::<RawPacket, 64>::new());

        let cmd_ring_clone = cmd_ring.clone();
        let pkt_ring_clone = pkt_ring.clone();
        let handle = thread::Builder::new()
            .name("raknet-server".into())
            .spawn(move || {
                server_loop(
                    socket,
                    cmd_ring_clone,
                    pkt_ring_clone,
                    my_guid,
                    max_connections,
                    ping_resp,
                );
            })
            .expect("thread spawn");

        self.mode = Mode::Active {
            cmd_ring,
            pkt_ring,
            _thread: handle,
            my_guid,
        };
        0
    }

    /// Returns 0 = RAKNET_STARTED, 2 = FAILED.
    pub fn startup_client(&mut self) -> u8 {
        if matches!(self.mode, Mode::Active { .. }) {
            return 1;
        }
        // Bind to any port; actual connect address set in `connect()`.
        let socket = match UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[raknet-sys] client bind: {e}");
                return 2;
            }
        };
        socket.set_read_timeout(Some(RECV_TIMEOUT)).ok();

        let my_guid = rand_guid();
        let cmd_ring = Arc::new(Ring::<Command, 64>::new());
        let pkt_ring = Arc::new(Ring::<RawPacket, 64>::new());

        let cmd_ring_clone = cmd_ring.clone();
        let pkt_ring_clone = pkt_ring.clone();
        let handle = thread::Builder::new()
            .name("raknet-client".into())
            .spawn(move || {
                client_loop(socket, cmd_ring_clone, pkt_ring_clone, my_guid);
            })
            .expect("thread spawn");

        self.mode = Mode::Active {
            cmd_ring,
            pkt_ring,
            _thread: handle,
            my_guid,
        };
        0
    }

    pub fn shutdown(&mut self, _block_ms: u32) {
        if let Mode::Active { cmd_ring, .. } = &self.mode {
            let _ = cmd_ring.try_push(Command::Shutdown);
        }
        self.mode = Mode::Idle;
    }

    pub fn is_active(&self) -> bool {
        matches!(self.mode, Mode::Active { .. })
    }

    pub fn set_offline_ping_response(&mut self, data: &[u8]) {
        let mut buf = Buffer::new();
        let len = data.len().min(256);
        buf.push_slice(&data[..len]);
        self.offline_ping_resp = buf.clone();
        if let Mode::Active { cmd_ring, .. } = &self.mode {
            let _ = cmd_ring.try_push(Command::SetPingResponse(buf));
        }
    }

    pub fn get_my_guid(&self) -> u64 {
        match &self.mode {
            Mode::Active { my_guid, .. } => *my_guid,
            Mode::Idle => 0,
        }
    }

    /// Returns 0 = CONNECTION_ATTEMPT_STARTED, 1 = error.
    pub fn connect(&mut self, host: &str, port: u16) -> u8 {
        match &self.mode {
            Mode::Active { cmd_ring, .. } => {
                let mut host_bytes = [0u8; 128];
                let host_slice = host.as_bytes();
                let len = host_slice.len().min(128);
                host_bytes[..len].copy_from_slice(&host_slice[..len]);
                let _ = cmd_ring.try_push(Command::ConnectClient {
                    host: host_bytes,
                    host_len: len,
                    port,
                });
                0
            }
            Mode::Idle => 1,
        }
    }

    pub fn ping(&mut self, host: &str, port: u16, _only_if_accepting: bool) {
        // Send an unconnected ping datagram directly.
        if let Mode::Active { cmd_ring, .. } = &self.mode {
            let ping = protocol::build_unconnected_ping(self.get_my_guid());
            let mut ping_buf = Buffer::<2048>::new();
            ping_buf.push_slice(ping.as_slice());
            let _ = cmd_ring.try_push(Command::Send {
                data: ping_buf,
                guid: 0,
                broadcast: false,
            });
            let _ = (host, port);
        }
    }

    pub fn send(
        &mut self,
        data: &[u8],
        _priority: u8,
        _reliability: u8,
        _channel: u8,
        guid: u64,
        broadcast: bool,
    ) -> bool {
        match &self.mode {
            Mode::Active { cmd_ring, .. } => {
                let mut buf = Buffer::new();
                let len = data.len().min(2048);
                buf.push_slice(&data[..len]);
                cmd_ring
                    .try_push(Command::Send {
                        data: buf,
                        guid,
                        broadcast,
                    })
                    .is_ok()
            }
            Mode::Idle => false,
        }
    }

    /// Non-blocking poll. Returns next queued packet or `None`.
    pub(crate) fn receive(&mut self) -> Option<RawPacket> {
        if let Mode::Active { pkt_ring, .. } = &self.mode {
            pkt_ring.try_pop()
        } else {
            None
        }
    }
}

// ---- background I/O loops ---------------------------------------------------

fn server_loop(
    socket: UdpSocket,
    cmd_ring: Arc<Ring<Command, 64>>,
    pkt_ring: Arc<Ring<RawPacket, 64>>,
    my_guid: u64,
    _max_connections: u32,
    mut ping_resp: Buffer<256>,
) {
    let mut offline = OfflineHandler::new(my_guid);
    let mut reliability: [Option<(SocketAddr, ReliabilityLayer)>; 64] =
        std::array::from_fn(|_| None);
    let mut buf = [0u8; 2048];

    loop {
        // Process commands.
        while let Some(cmd) = cmd_ring.try_pop() {
            match cmd {
                Command::Shutdown => return,
                Command::SetPingResponse(r) => ping_resp = r,
                Command::Send {
                    data,
                    guid,
                    broadcast,
                } => {
                    if broadcast {
                        for slot in reliability.iter_mut() {
                            if let Some((addr, layer)) = slot {
                                let frame = layer.send(data.as_slice());
                                socket.send_to(frame.as_slice(), *addr).ok();
                            }
                        }
                    } else if let Some(addr) = find_addr_by_guid(&offline, guid) {
                        for slot in reliability.iter_mut() {
                            if let Some((slot_addr, layer)) = slot {
                                if *slot_addr == addr {
                                    let frame = layer.send(data.as_slice());
                                    socket.send_to(frame.as_slice(), addr).ok();
                                    break;
                                }
                            }
                        }
                    }
                }
                _ => {}
            }
        }

        // Receive incoming datagrams.
        match socket.recv_from(&mut buf) {
            Ok((len, src)) => {
                let datagram = &buf[..len];

                if protocol::is_offline(datagram) {
                    // Handle offline (pre-connection) packets.
                    if let Some(response) = offline.handle(datagram, src, ping_resp.as_slice()) {
                        socket.send_to(response.as_slice(), src).ok();
                    }
                    // Notify game thread of new connection if handshake complete.
                    if offline.just_connected(src) {
                        let peer_guid = offline.guid_for(src).unwrap_or(0);
                        let mut new_incoming = Buffer::new();
                        new_incoming.push(protocol::ID_NEW_INCOMING_CONNECTION);
                        let _ = pkt_ring.try_push(RawPacket {
                            data: new_incoming,
                            guid: peer_guid,
                            addr: src,
                        });
                        // Insert new reliability layer
                        for slot in reliability.iter_mut() {
                            if slot.is_none() {
                                *slot = Some((src, ReliabilityLayer::new()));
                                break;
                            }
                        }
                    }
                } else {
                    let mut layer_idx = None;
                    for (i, slot) in reliability.iter().enumerate() {
                        if let Some((addr, _)) = slot {
                            if *addr == src {
                                layer_idx = Some(i);
                                break;
                            }
                        }
                    }

                    if layer_idx.is_none() && offline.guid_for(src).is_some() {
                        for (i, slot) in reliability.iter_mut().enumerate() {
                            if slot.is_none() {
                                *slot = Some((src, ReliabilityLayer::new()));
                                layer_idx = Some(i);
                                break;
                            }
                        }
                    }

                    if let Some(idx) = layer_idx {
                        let (_, layer) = reliability[idx].as_mut().unwrap();
                        let peer_guid = offline.guid_for(src).unwrap_or(0);
                        for frame in layer.receive(datagram) {
                            if let Some(ack) = frame.ack_payload() {
                                socket.send_to(ack, src).ok();
                            }
                            if let Some(user_data) = frame.user_data() {
                                let _ = pkt_ring.try_push(RawPacket {
                                    data: user_data,
                                    guid: peer_guid,
                                    addr: src,
                                });
                            }
                        }
                    }
                }
            }
            Err(ref e) if is_timeout(e) => {}
            Err(e) => eprintln!("[raknet-sys] recv: {e}"),
        }
    }
}

fn client_loop(
    socket: UdpSocket,
    cmd_ring: Arc<Ring<Command, 64>>,
    pkt_ring: Arc<Ring<RawPacket, 64>>,
    my_guid: u64,
) {
    let mut server_addr: Option<SocketAddr> = None;
    let mut server_guid: u64 = 0;
    let mut handshake: Option<protocol::ClientHandshake> = None;
    let mut reliability: Option<ReliabilityLayer> = None;
    let mut buf = [0u8; 2048];
    let mut last_connect_attempt = Instant::now()
        .checked_sub(Duration::from_secs(10))
        .unwrap_or_else(Instant::now);

    loop {
        while let Some(cmd) = cmd_ring.try_pop() {
            match cmd {
                Command::Shutdown => return,
                Command::ConnectClient {
                    host,
                    host_len,
                    port,
                } => {
                    let host_str = std::str::from_utf8(&host[..host_len]).unwrap_or("127.0.0.1");
                    let addr_str = format!("{host_str}:{port}");
                    if let Ok(addr) = addr_str.parse::<SocketAddr>() {
                        server_addr = Some(addr);
                        handshake = Some(protocol::ClientHandshake::new(my_guid));
                        last_connect_attempt = Instant::now()
                            .checked_sub(Duration::from_secs(10))
                            .unwrap_or_else(Instant::now);
                    } else {
                        eprintln!("[raknet-sys] bad addr: {addr_str}");
                        let mut fail_data = Buffer::new();
                        fail_data.push(protocol::ID_CONNECTION_ATTEMPT_FAILED);
                        let _ = pkt_ring.try_push(RawPacket {
                            data: fail_data,
                            guid: 0,
                            addr: "0.0.0.0:0".parse().unwrap(),
                        });
                    }
                }
                Command::Send { data, .. } => {
                    if let (Some(addr), Some(layer)) = (server_addr, reliability.as_mut()) {
                        let frame = layer.send(data.as_slice());
                        socket.send_to(frame.as_slice(), addr).ok();
                    }
                }
                _ => {}
            }
        }

        // Drive connection handshake.
        if let (Some(addr), Some(hs)) = (server_addr, handshake.as_mut()) {
            if last_connect_attempt.elapsed() > Duration::from_millis(500) {
                if let Some(pkt) = hs.next_outgoing() {
                    socket.send_to(pkt.as_slice(), addr).ok();
                    last_connect_attempt = Instant::now();
                }
            }
        }

        match socket.recv_from(&mut buf) {
            Ok((len, src)) => {
                let datagram = &buf[..len];
                if Some(src) != server_addr {
                    continue;
                }

                if protocol::is_offline(datagram) {
                    if let Some(hs) = handshake.as_mut() {
                        // After OCR1 reply, supply the actual server addr for OCR2.
                        hs.advance_to_ocr2(src);
                        match hs.handle(datagram) {
                            protocol::HandshakeResult::Continue(response) => {
                                socket.send_to(response.as_slice(), src).ok();
                            }
                            protocol::HandshakeResult::Connected(guid) => {
                                server_guid = guid;
                                reliability = Some(ReliabilityLayer::new());
                                handshake = None;
                                let mut accept_data = Buffer::new();
                                accept_data.push(protocol::ID_CONNECTION_REQUEST_ACCEPTED);
                                let _ = pkt_ring.try_push(RawPacket {
                                    data: accept_data,
                                    guid,
                                    addr: src,
                                });
                            }
                            protocol::HandshakeResult::Failed => {
                                handshake = None;
                                let mut fail_data = Buffer::new();
                                fail_data.push(protocol::ID_CONNECTION_ATTEMPT_FAILED);
                                let _ = pkt_ring.try_push(RawPacket {
                                    data: fail_data,
                                    guid: 0,
                                    addr: src,
                                });
                            }
                            protocol::HandshakeResult::Pending => {}
                        }
                    }
                } else if let Some(layer) = reliability.as_mut() {
                    for frame in layer.receive(datagram) {
                        if let Some(ack) = frame.ack_payload() {
                            socket.send_to(ack, src).ok();
                        }
                        if let Some(user_data) = frame.user_data() {
                            let _ = pkt_ring.try_push(RawPacket {
                                data: user_data,
                                guid: server_guid,
                                addr: src,
                            });
                        }
                    }
                }
            }
            Err(ref e) if is_timeout(e) => {}
            Err(e) => eprintln!("[raknet-sys] recv: {e}"),
        }
    }
}

// ---- helpers ----------------------------------------------------------------

fn find_addr_by_guid(offline: &OfflineHandler, guid: u64) -> Option<SocketAddr> {
    for slot in offline.connected.iter() {
        if let Some((addr, slot_guid)) = slot {
            if *slot_guid == guid {
                return Some(*addr);
            }
        }
    }
    None
}

// ---- helpers ----------------------------------------------------------------

fn rand_guid() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    let t = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64;
    t ^ ((std::process::id() as u64).wrapping_mul(0x9e3779b97f4a7c15))
}

fn is_timeout(e: &std::io::Error) -> bool {
    matches!(
        e.kind(),
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
    )
}
