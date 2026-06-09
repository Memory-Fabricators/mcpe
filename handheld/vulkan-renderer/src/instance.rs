// vulkan_renderer/src/instance.rs — Vulkan instance via ash (manual loading).

use ash::khr;
use ash::vk;
use std::ffi::{c_char, c_void, CStr};

// Raw FFI for dynamic loading
unsafe extern "C" {
    fn dlopen(path: *const c_char, mode: i32) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}
const RTLD_NOW: i32 = 2;

pub struct InstanceCtx {
    /// ash instance wrapper with loaded instance-level functions.
    pub inner: ash::Instance,
    /// KHR surface extension functions.
    pub surface_ext: khr::surface::Instance,
}

pub fn create() -> Result<InstanceCtx, String> {
    let entry = unsafe { load_entry()? };

    let app_name = CStr::from_bytes_with_nul(b"mcpe\0").unwrap();
    let engine_name = CStr::from_bytes_with_nul(b"mcpe_vulkan\0").unwrap();

    let app_info = vk::ApplicationInfo::default()
        .application_name(app_name)
        .application_version(vk::make_api_version(0, 2, 0, 0))
        .engine_name(engine_name)
        .engine_version(vk::make_api_version(0, 1, 0, 0))
        .api_version(vk::API_VERSION_1_3);

    let enabled_extensions = get_required_extensions()?;

    let create_info = vk::InstanceCreateInfo::default()
        .application_info(&app_info)
        .enabled_extension_names(&enabled_extensions);

    let instance = unsafe {
        entry
            .create_instance(&create_info, None)
            .map_err(|e| format!("vkCreateInstance failed: {e}"))?
    };

    let surface_ext = khr::surface::Instance::load(&entry, &instance);

    Ok(InstanceCtx {
        inner: instance,
        surface_ext,
    })
}

unsafe fn load_entry() -> Result<ash::Entry, String> {
    #[cfg(target_os = "macos")]
    let lib_paths = [b"libvulkan.dylib\0".as_ptr() as *const c_char,
                      b"libMoltenVK.dylib\0".as_ptr() as *const c_char];
    #[cfg(target_os = "linux")]
    let lib_paths = [b"libvulkan.so.1\0".as_ptr() as *const c_char];
    #[cfg(target_os = "windows")]
    let lib_paths = [b"vulkan-1.dll\0".as_ptr() as *const c_char];

    let mut lib = std::ptr::null_mut();
    for path in lib_paths {
        lib = dlopen(path, RTLD_NOW);
        if !lib.is_null() {
            break;
        }
    }
    if lib.is_null() {
        return Err("Failed to load Vulkan library".into());
    }

    let get_proc_addr: vk::PFN_vkGetInstanceProcAddr = {
        let sym = dlsym(lib, b"vkGetInstanceProcAddr\0".as_ptr() as *const c_char);
        if sym.is_null() {
            return Err("Failed to find vkGetInstanceProcAddr".into());
        }
        // PFN_vkGetInstanceProcAddr in ash is a bare unsafe extern "system" fn,
        // so transmuting from a raw pointer is valid.
        std::mem::transmute(sym)
    };

    let static_fn = ash::StaticFn::load(|name| {
        let ptr = get_proc_addr(vk::Instance::null(), name.as_ptr());
        // ptr is PFN_vkVoidFunction = Option<unsafe extern "system" fn()>
        // Option<fn> uses niche optimization: None = null pointer.
        // Cast through transmute to convert to *const c_void.
        if ptr.is_none() {
            std::ptr::null()
        } else {
            ptr.unwrap() as *const c_void
        }
    });

    Ok(ash::Entry::from_static_fn(static_fn))
}

impl Drop for InstanceCtx {
    fn drop(&mut self) {
        unsafe {
            self.inner.destroy_instance(None);
        }
    }
}

fn get_required_extensions() -> Result<Vec<*const c_char>, String> {
    let mut exts: Vec<&CStr> = vec![khr::surface::NAME];

    #[cfg(target_os = "macos")]
    {
        exts.push(ash::ext::metal_surface::NAME);
        exts.push(ash::mvk::macos_surface::NAME);
    }
    #[cfg(target_os = "linux")]
    {
        exts.push(ash::khr::xlib_surface::NAME);
        exts.push(ash::khr::wayland_surface::NAME);
    }
    #[cfg(target_os = "windows")]
    {
        exts.push(ash::khr::win32_surface::NAME);
    }

    Ok(exts.into_iter().map(CStr::as_ptr).collect())
}
