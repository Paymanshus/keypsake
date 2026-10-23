//! App icons from the exe itself, as PNG bytes for the UI.

use crate::apps::wide;
use windows::core::PCWSTR;
use windows::Win32::Graphics::Gdi::{
    CreateCompatibleDC, DeleteDC, DeleteObject, GetDIBits, GetObjectW, BITMAP, BITMAPINFO, BITMAPINFOHEADER, BI_RGB,
    DIB_RGB_COLORS, HGDIOBJ,
};
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, RRF_RT_REG_SZ};
use windows::Win32::UI::WindowsAndMessaging::{DestroyIcon, GetIconInfo, PrivateExtractIconsW, HICON, ICONINFO};

/// `bundle` is an exe path, or just an exe name (demo data): then App Paths in the registry is asked.
pub fn resolve(bundle: &str) -> Option<String> {
    if bundle.contains('\\') || bundle.contains('/') {
        return Some(bundle.to_string());
    }
    let key = wide(&format!("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\{bundle}"));
    for root in [HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE] {
        let mut buf = vec![0u16; 1024];
        let mut len = (buf.len() * 2) as u32;
        let ok = unsafe {
            RegGetValueW(
                root,
                PCWSTR(key.as_ptr()),
                PCWSTR::null(),
                RRF_RT_REG_SZ,
                None,
                Some(buf.as_mut_ptr() as _),
                Some(&mut len),
            )
        };
        if ok.is_ok() {
            let end = buf.iter().position(|&c| c == 0).unwrap_or(0);
            return Some(String::from_utf16_lossy(&buf[..end]).trim_matches('"').to_string());
        }
    }
    let sys = std::env::var("WINDIR").ok()? + "\\System32\\" + bundle;
    std::path::Path::new(&sys).exists().then_some(sys)
}

pub fn exe_icon_png(bundle: &str, size: u32) -> Option<Vec<u8>> {
    let path = resolve(bundle)?;
    let w = wide(&path);
    let mut buf = [0u16; 260];
    let n = w.len().min(259);
    buf[..n].copy_from_slice(&w[..n]);
    let mut icon = [HICON::default()];
    let got = unsafe { PrivateExtractIconsW(&buf, 0, size as i32, size as i32, Some(&mut icon), None, 0) };
    if got == 0 || got == u32::MAX || icon[0].is_invalid() {
        return None;
    }
    let png = unsafe { icon_to_png(icon[0]) };
    unsafe {
        let _ = DestroyIcon(icon[0]);
    }
    png
}

unsafe fn icon_to_png(icon: HICON) -> Option<Vec<u8>> {
    let mut info = ICONINFO::default();
    GetIconInfo(icon, &mut info).ok()?;
    let result = (|| {
        let mut bm = BITMAP::default();
        if GetObjectW(HGDIOBJ(info.hbmColor.0), std::mem::size_of::<BITMAP>() as i32, Some(&mut bm as *mut _ as _)) == 0
        {
            return None;
        }
        let (w, h) = (bm.bmWidth, bm.bmHeight);
        let mut bmi = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: w,
                biHeight: -h,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut px = vec![0u8; (w * h * 4) as usize];
        let dc = CreateCompatibleDC(None);
        let rows = GetDIBits(dc, info.hbmColor, 0, h as u32, Some(px.as_mut_ptr() as _), &mut bmi, DIB_RGB_COLORS);
        let _ = DeleteDC(dc);
        if rows == 0 {
            return None;
        }
        let has_alpha = px.chunks(4).any(|p| p[3] != 0);
        for p in px.chunks_mut(4) {
            p.swap(0, 2); // BGRA -> RGBA
            if !has_alpha {
                p[3] = 255;
            }
        }
        let mut out = Vec::new();
        let mut enc = png::Encoder::new(&mut out, w as u32, h as u32);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        enc.write_header().ok()?.write_image_data(&px).ok()?;
        Some(out)
    })();
    let _ = DeleteObject(HGDIOBJ(info.hbmColor.0));
    let _ = DeleteObject(HGDIOBJ(info.hbmMask.0));
    result
}
