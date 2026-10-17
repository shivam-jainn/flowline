//! Plugin manifest + registration for the `windows` driver (R/M3-01).

use stepit_ir::PluginManifest;

/// The versioned manifest the host registry resolves (`windows` alongside
/// `mac` / `mock` / `noop`).
pub fn windows_manifest() -> PluginManifest {
    PluginManifest {
        id: "windows".to_string(),
        version: "1.0.0".to_string(),
        capabilities: vec![
            "snapshots".to_string(),
            "micro-clips".to_string(),
            "accessibility-tree".to_string(),
            "secure-field-detection".to_string(),
        ],
        minimum_host_version: "r-m1".to_string(),
    }
}

/// Registered driver plugin: manifest + capability query surface.
/// The host owns hook lifetimes; this descriptor is data, not a handle.
#[derive(Debug, Clone)]
pub struct DriverPlugin {
    pub manifest: PluginManifest,
}

impl DriverPlugin {
    pub fn supports_streaming(&self) -> bool {
        true
    }

    pub fn needs_screen_access(&self) -> bool {
        self.manifest.supports("snapshots")
    }
}

/// The one registration line: build the plugin the host registry stores.
pub fn register() -> DriverPlugin {
    DriverPlugin {
        manifest: windows_manifest(),
    }
}

pub use windows_manifest as manifest;

/// Live Win32 hook pumping (`cfg(windows)` only).
///
/// Hand-declared `extern "system"` surface (no `windows-rs` dependency — the
/// build environment cannot verify that linkage). Parses on every host;
/// links and runs on Windows only.
#[cfg(windows)]
pub mod win32 {
    /// Low-level mouse hook id for `SetWindowsHookExW`.
    pub const WH_MOUSE_LL: i32 = 14;
    /// Low-level keyboard hook id.
    pub const WH_KEYBOARD_LL: i32 = 13;

    #[repr(C)]
    #[derive(Debug, Clone, Copy)]
    pub struct Point {
        pub x: i32,
        pub y: i32,
    }

    #[repr(C)]
    #[derive(Debug, Clone, Copy)]
    pub struct MsllHookStruct {
        pub pt: Point,
        pub mouse_data: u32,
        pub flags: u32,
        pub time: u32,
        pub dw_extra_info: usize,
    }

    #[repr(C)]
    #[derive(Debug, Clone, Copy)]
    pub struct KbdllHookStruct {
        pub vk_code: u32,
        pub scan_code: u32,
        pub flags: u32,
        pub time: u32,
        pub dw_extra_info: usize,
    }

    pub type HookProc =
        unsafe extern "system" fn(code: i32, w_param: usize, l_param: isize) -> isize;
    pub type HookHandle = isize;

    unsafe extern "system" {
        pub fn SetWindowsHookExW(
            id_hook: i32,
            lpfn: HookProc,
            hmod: *const core::ffi::c_void,
            dw_thread_id: u32,
        ) -> HookHandle;
        pub fn UnhookWindowsHookEx(hhk: HookHandle) -> i32;
        pub fn CallNextHookEx(
            hhk: HookHandle,
            n_code: i32,
            w_param: usize,
            l_param: isize,
        ) -> isize;
    }

    /// Install the mouse + keyboard hooks; returns opaque handles.
    /// Callbacks normalize via `crate::hooks` and forward IR to the engine.
    pub fn install_hooks(
        mouse_proc: HookProc,
        keyboard_proc: HookProc,
    ) -> (HookHandle, HookHandle) {
        unsafe {
            let mouse = SetWindowsHookExW(WH_MOUSE_LL, mouse_proc, core::ptr::null(), 0);
            let keyboard =
                SetWindowsHookExW(WH_KEYBOARD_LL, keyboard_proc, core::ptr::null(), 0);
            (mouse, keyboard)
        }
    }
}
