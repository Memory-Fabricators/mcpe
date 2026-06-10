use std::ffi::{CStr, c_char};

#[repr(C)]
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct RakNetGUID {
    pub g: u64,
    pub system_index: u16,
}

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct SystemAddress {
    pub sin_family_or_len: u16,
    pub sin_port: u16,
    pub sin_addr: u32,
    pub sin_zero: [u8; 8],
    pub debug_port: u16,
    pub system_index: u16,
}

impl Default for SystemAddress {
    fn default() -> Self {
        Self {
            sin_family_or_len: 2, // AF_INET
            sin_port: 0,
            sin_addr: 0,
            sin_zero: [0; 8],
            debug_port: 0,
            system_index: 0xffff,
        }
    }
}

impl SystemAddress {
    pub fn get_port(&self) -> u16 {
        u16::from_be(self.sin_port)
    }
}

#[repr(C)]
pub struct RakString {
    pub shared_string: *const std::ffi::c_void,
}

impl RakString {
    pub unsafe fn as_c_str(&self) -> *const c_char {
        if self.shared_string.is_null() {
            return std::ptr::null();
        }
        // In C++ SharedString, c_str is at offset 32 on 64-bit systems
        let c_str_ptr =
            unsafe { (self.shared_string as *const u8).add(32) as *const *const c_char };
        unsafe { *c_str_ptr }
    }
}

// ---- RakNetGUID FFI Exports ----

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_guid_to_string(guid: *const RakNetGUID, dest: *mut c_char) {
    if guid.is_null() || dest.is_null() {
        return;
    }
    let g_val = unsafe { (*guid).g };
    let s = if g_val == 0xFFFFFFFFFFFFFFFF {
        "UNASSIGNED_RAKNET_GUID\0".to_string()
    } else {
        format!("{g_val}\0")
    };
    let bytes = s.as_bytes();
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, dest, bytes.len());
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_guid_to_string_static(guid: *const RakNetGUID) -> *const c_char {
    use std::sync::atomic::{AtomicU8, Ordering};
    static STR_INDEX: AtomicU8 = AtomicU8::new(0);
    static mut STR: [[c_char; 64]; 8] = [[0; 64]; 8];

    let idx = STR_INDEX.fetch_add(1, Ordering::Relaxed) & 7;
    let dest = unsafe { &mut STR[idx as usize] };
    raknet_guid_to_string(guid, dest.as_mut_ptr());
    dest.as_ptr()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_guid_from_string(
    guid: *mut RakNetGUID,
    source: *const c_char,
) -> bool {
    if guid.is_null() || source.is_null() {
        return false;
    }
    let c_str = unsafe { CStr::from_ptr(source) };
    let s = match c_str.to_str() {
        Ok(v) => v,
        Err(_) => return false,
    };
    if let Ok(val) = s.parse::<u64>() {
        unsafe {
            (*guid).g = val;
        }
        true
    } else {
        false
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_guid_to_uint32(guid: *const RakNetGUID) -> u32 {
    if guid.is_null() {
        return 0;
    }
    let g_val = unsafe { (*guid).g };
    ((g_val >> 32) ^ (g_val & 0xFFFFFFFF)) as u32
}

// ---- SystemAddress FFI Exports ----

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_system_address_get_port(addr: *const SystemAddress) -> u16 {
    if addr.is_null() {
        return 0;
    }
    unsafe { (*addr).get_port() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_system_address_to_string(
    addr: *const SystemAddress,
    write_port: bool,
    dest: *mut c_char,
    port_delineator: c_char,
) {
    if addr.is_null() || dest.is_null() {
        return;
    }
    let system_addr = unsafe { &*addr };
    let ip_u32 = u32::from_be(system_addr.sin_addr);
    let octets = [
        ((ip_u32 >> 24) & 0xff) as u8,
        ((ip_u32 >> 16) & 0xff) as u8,
        ((ip_u32 >> 8) & 0xff) as u8,
        (ip_u32 & 0xff) as u8,
    ];
    let ip_str = format!("{}.{}.{}.{}", octets[0], octets[1], octets[2], octets[3]);

    let s = if write_port {
        let port = system_addr.get_port();
        let delim = port_delineator as u8 as char;
        format!("{ip_str}{delim}{port}\0")
    } else {
        format!("{ip_str}\0")
    };

    let bytes = s.as_bytes();
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, dest, bytes.len());
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_system_address_to_string_static(
    addr: *const SystemAddress,
    write_port: bool,
    port_delineator: c_char,
) -> *const c_char {
    use std::sync::atomic::{AtomicU8, Ordering};
    static STR_INDEX: AtomicU8 = AtomicU8::new(0);
    static mut STR: [[c_char; 128]; 8] = [[0; 128]; 8];

    let idx = STR_INDEX.fetch_add(1, Ordering::Relaxed) & 7;
    let dest = unsafe { &mut STR[idx as usize] };
    raknet_system_address_to_string(addr, write_port, dest.as_mut_ptr(), port_delineator);
    dest.as_ptr()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn raknet_system_address_equals(
    a: *const SystemAddress,
    b: *const SystemAddress,
) -> bool {
    if a.is_null() || b.is_null() {
        return false;
    }
    let sa = unsafe { &*a };
    let sb = unsafe { &*b };
    sa.sin_family_or_len == sb.sin_family_or_len
        && sa.sin_port == sb.sin_port
        && sa.sin_addr == sb.sin_addr
        && sa.sin_zero == sb.sin_zero
}

// ---- RakString FFI Exports ----

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rakstring_is_empty(s: *const RakString) -> bool {
    if s.is_null() {
        return true;
    }
    let c_ptr = unsafe { (*s).as_c_str() };
    if c_ptr.is_null() {
        return true;
    }
    unsafe { *c_ptr == 0 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rakstring_get_length(s: *const RakString) -> usize {
    if s.is_null() {
        return 0;
    }
    let c_ptr = unsafe { (*s).as_c_str() };
    if c_ptr.is_null() {
        return 0;
    }
    unsafe { std::ffi::CStr::from_ptr(c_ptr).to_bytes().len() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rakstring_strcmp(a: *const RakString, b: *const RakString) -> i32 {
    if a.is_null() || b.is_null() {
        return 0;
    }
    let c_a = unsafe { (*a).as_c_str() };
    let c_b = unsafe { (*b).as_c_str() };
    if c_a.is_null() && c_b.is_null() {
        return 0;
    }
    if c_a.is_null() {
        return -1;
    }
    if c_b.is_null() {
        return 1;
    }
    unsafe { std::ffi::CStr::from_ptr(c_a).cmp(std::ffi::CStr::from_ptr(c_b)) as i32 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rakstring_equals_str(s: *const RakString, str_ptr: *const c_char) -> bool {
    if s.is_null() {
        return str_ptr.is_null();
    }
    let c_a = unsafe { (*s).as_c_str() };
    if c_a.is_null() {
        return str_ptr.is_null();
    }
    if str_ptr.is_null() {
        return false;
    }
    unsafe { std::ffi::CStr::from_ptr(c_a) == std::ffi::CStr::from_ptr(str_ptr) }
}
