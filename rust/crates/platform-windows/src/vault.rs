//! The database key, wrapped with DPAPI so only this Windows user can unwrap it (the Keychain's role on macOS).

use anyhow::{bail, Context, Result};
use std::path::Path;
use windows::Win32::Foundation::{LocalFree, HLOCAL};
use windows::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
};

fn protect(data: &[u8]) -> Result<Vec<u8>> {
    unsafe {
        let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
        let mut out = CRYPT_INTEGER_BLOB::default();
        CryptProtectData(&input, None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out)?;
        let v = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
        let _ = LocalFree(Some(HLOCAL(out.pbData as _)));
        Ok(v)
    }
}

fn unprotect(data: &[u8]) -> Result<Vec<u8>> {
    unsafe {
        let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 };
        let mut out = CRYPT_INTEGER_BLOB::default();
        CryptUnprotectData(&input, None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out)?;
        let v = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
        let _ = LocalFree(Some(HLOCAL(out.pbData as _)));
        Ok(v)
    }
}

/// Loads the key, or makes one on first run. If a key file exists but can't be unwrapped, this fails
/// instead of minting a new key: a new key would orphan the existing history.
pub fn load_key(file: &Path) -> Result<[u8; 32]> {
    if file.exists() {
        let wrapped = std::fs::read(file).with_context(|| format!("reading {}", file.display()))?;
        let key = unprotect(&wrapped).context("Windows couldn't unlock the key (DPAPI)")?;
        let Ok(key) = <[u8; 32]>::try_from(key.as_slice()) else { bail!("the key file is damaged") };
        return Ok(key);
    }
    let key = keypsake_core::store::new_key();
    let tmp = file.with_extension("tmp");
    std::fs::write(&tmp, protect(&key)?)?;
    std::fs::rename(&tmp, file)?;
    Ok(key)
}
