mod bitstream;
mod buffer;
mod peer;
mod protocol;
mod types;

use peer::RakPeer;
use std::ffi::CStr;

#[unsafe(no_mangle)]
pub extern "C" fn raknet_peer_create() -> *mut RakPeer {
    Box::into_raw(Box::new(RakPeer::new()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_destroy(peer: *mut RakPeer) {
    if !peer.is_null() {
        drop(unsafe { Box::from_raw(peer) });
    }
}

// --- startup / shutdown ---

/// Returns: 0 = RAKNET_STARTED, 1 = RAKNET_ALREADY_STARTED, 2 = INVALID_SOCKET_DESCRIPTORS
#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_startup_server(
    peer: *mut RakPeer,
    max_connections: u32,
    port: u16,
) -> u8 {
    unsafe { &mut *peer }.startup_server(max_connections, port)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_startup_client(peer: *mut RakPeer) -> u8 {
    unsafe { &mut *peer }.startup_client()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_shutdown(peer: *mut RakPeer, block_ms: u32) {
    unsafe { &mut *peer }.shutdown(block_ms);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_is_active(peer: *const RakPeer) -> bool {
    unsafe { &*peer }.is_active()
}

// --- configuration ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_set_max_incoming(peer: *mut RakPeer, n: u32) {
    // stored in peer mode at startup time; this is a no-op after startup
    let _ = (peer, n);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_set_timeout_time(peer: *mut RakPeer, ms: u32) {
    // TODO: forward to connection timeout on rak-rs side
    let _ = (peer, ms);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_set_occasional_ping(peer: *mut RakPeer, enabled: bool) {
    let _ = (peer, enabled);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_set_offline_ping_response(
    peer: *mut RakPeer,
    data: *const u8,
    len: u32,
) {
    let slice = unsafe { std::slice::from_raw_parts(data, len as usize) };
    unsafe { &mut *peer }.set_offline_ping_response(slice);
}

// --- identity ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_get_my_guid(peer: *const RakPeer) -> u64 {
    unsafe { &*peer }.get_my_guid()
}

// --- connect / ping ---

/// Returns: 0 = CONNECTION_ATTEMPT_STARTED, non-zero = error
#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_connect(
    peer: *mut RakPeer,
    host: *const std::ffi::c_char,
    port: u16,
) -> u8 {
    let host = unsafe { CStr::from_ptr(host) }
        .to_str()
        .unwrap_or("127.0.0.1");
    unsafe { &mut *peer }.connect(host, port)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_ping(
    peer: *mut RakPeer,
    host: *const std::ffi::c_char,
    port: u16,
    only_if_accepting: bool,
) {
    let host = unsafe { CStr::from_ptr(host) }
        .to_str()
        .unwrap_or("255.255.255.255");
    unsafe { &mut *peer }.ping(host, port, only_if_accepting);
}

// --- send / receive ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_receive(
    peer: *mut RakPeer,
    out_data: *mut *mut u8,
    out_len: *mut u32,
    out_guid: *mut u64,
    out_port: *mut u16,
    out_ip: *mut u8,
) -> bool {
    if peer.is_null()
        || out_data.is_null()
        || out_len.is_null()
        || out_guid.is_null()
        || out_port.is_null()
        || out_ip.is_null()
    {
        return false;
    }

    let peer_ref = unsafe { &mut *peer };
    if let Some(pkt) = peer_ref.receive() {
        let slice = pkt.data.as_slice();
        let len = slice.len();

        let mut vec = slice.to_vec();
        let ptr = vec.as_mut_ptr();
        std::mem::forget(vec); // Hand memory over to C++

        unsafe {
            *out_data = ptr;
            *out_len = len as u32;
            *out_guid = pkt.guid;
            *out_port = pkt.addr.port();

            // Format IP address into out_ip
            let ip_str = match pkt.addr {
                std::net::SocketAddr::V4(a) => a.ip().to_string(),
                std::net::SocketAddr::V6(a) => a.ip().to_string(),
            };
            let bytes = ip_str.as_bytes();
            let n = bytes.len().min(45);
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ip, n);
            *out_ip.add(n) = 0; // Null-terminator
        }
        true
    } else {
        false
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_deallocate_data(data: *mut u8, len: u32) {
    if !data.is_null() && len > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(data, len as usize, len as usize);
        }
    }
}

/// `guid = 0` with `broadcast = true` broadcasts to all connected peers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_peer_send(
    peer: *mut RakPeer,
    data: *const u8,
    len: u32,
    priority: u8,
    reliability: u8,
    channel: u8,
    guid: u64,
    broadcast: bool,
) -> bool {
    let slice = unsafe { std::slice::from_raw_parts(data, len as usize) };
    unsafe { &mut *peer }.send(slice, priority, reliability, channel, guid, broadcast)
}
