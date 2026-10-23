<script>
  // SettingsView in Settings.swift.
  import { app, setPrefs } from "./state.svelte.js";
  import { call, fitWindow } from "./api.js";
  import Chips from "./Chips.svelte";
  import ShortcutRecorder from "./ShortcutRecorder.svelte";
  import Toggle from "./Toggle.svelte";
  import WindowControls from "./WindowControls.svelte";

  const p = $derived(app.status.prefs);
  let openAtLogin = $state(false);
  let loginError = $state(null);
  let confirmDelete = $state(false);

  $effect(() => {
    call("autostart").then((v) => (openAtLogin = v));
    fitWindow(480);
  });

  async function setLogin(on) {
    openAtLogin = on;
    try {
      await call("set_autostart", { on });
      loginError = null;
    } catch (e) {
      loginError = String(e);
      openAtLogin = !on;
    }
  }
</script>

<div class="top" data-tauri-drag-region><WindowControls minimize={false} maximize={false} /></div>
<div class="settings">
  <h1 class="display" data-tauri-drag-region>Settings</h1>

  <section>
    <h2 class="mono faint">RECORDING</h2>
    <div class="row"><div class="label">Record typing and copies</div>
      <Toggle label="Record typing and copies" on={!p.paused} onchange={(v) => setPrefs({ paused: !v })} /></div>
    <div class="row"><div class="label">Open at login{#if loginError}<div class="note faint">{loginError}</div>{/if}</div>
      <Toggle label="Open at login" on={openAtLogin} onchange={setLogin} /></div>
    {#if app.status.typingError}
      <div class="row"><div class="label">Typing<div class="note faint">{app.status.typingError}</div></div>
        <span class="mono soft small">Off</span></div>
    {/if}
  </section>

  <section>
    <h2 class="mono faint">KEEP</h2>
    <div class="row"><div class="label">Typed text for</div>
      <Chips options={[[7, "7d"], [30, "30d"], [90, "90d"], [365, "1y"]]} value={p.retentionDays} onpick={(v) => setPrefs({ retentionDays: v })} /></div>
    <div class="row"><div class="label">Copies to keep</div>
      <Chips options={[25, 50, 100, 250, 500].map((n) => [n, String(n)])} value={p.clipLimit} onpick={(v) => setPrefs({ clipLimit: v })} /></div>
  </section>

  <section>
    <h2 class="mono faint">SHORTCUTS</h2>
    <div class="row"><div class="label">Open keypsake</div>
      <ShortcutRecorder value={p.shortcutOpen} onchange={(v) => setPrefs({ shortcutOpen: v })} /></div>
    <div class="row"><div class="label">Pause or resume recording{#if app.status.shortcutError}<div class="note faint">{app.status.shortcutError}</div>{/if}</div>
      <ShortcutRecorder value={p.shortcutPause} onchange={(v) => setPrefs({ shortcutPause: v })} /></div>
  </section>

  <section>
    <h2 class="mono faint">PRIVACY</h2>
    <p class="soft">History is encrypted on this PC and never leaves it. Password fields and password managers are never recorded. Site icons are fetched from the site itself.</p>
    <div class="row"><div class="label">Delete all history</div>
      <button class="pill" onclick={() => (confirmDelete = true)}>Delete all</button></div>
  </section>
</div>

{#if confirmDelete}
  <div class="scrim">
    <div class="dialog" role="alertdialog" aria-labelledby="del-title">
      <div id="del-title" class="medium">Delete all typed text and copies?</div>
      <div class="soft">This can't be undone.</div>
      <div class="buttons">
        <button class="pill" onclick={() => (confirmDelete = false)}>Cancel</button>
        <button class="pill danger" onclick={() => { call("delete_all"); confirmDelete = false; }}>Delete all</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .top { position: fixed; top: 0; left: 0; right: 0; height: 32px; display: flex; justify-content: flex-end; }
  .settings { width: 480px; padding: 68px 30px 28px; }
  h1 { font-size: 28px; font-weight: 400; margin: 0 0 22px; }
  section { margin-bottom: 22px; }
  section:last-child { margin-bottom: 0; }
  h2 { font-size: 9.5px; letter-spacing: 1.2px; font-weight: 400; margin: 0 0 6px; }
  .row { min-height: 40px; display: flex; align-items: center; justify-content: space-between; gap: 12px; border-bottom: 1px solid color-mix(in srgb, var(--ghost) 42%, transparent); }
  .label { font-size: 13px; display: flex; flex-direction: column; gap: 2px; }
  .note { font-size: 11px; }
  .small { font-size: 11px; }
  p { font-size: 11.5px; line-height: 17px; margin: 0; padding: 10px 0; }
  .scrim { position: fixed; inset: 0; background: color-mix(in srgb, var(--ink) 25%, transparent); display: flex; align-items: center; justify-content: center; }
  .dialog { width: 320px; padding: 20px; border-radius: 10px; background: var(--ground); display: flex; flex-direction: column; gap: 6px; font-size: 13px; box-shadow: 0 12px 40px rgb(0 0 0 / 0.25); }
  .buttons { display: flex; justify-content: flex-end; gap: 8px; margin-top: 12px; }
  .danger { background: #c42b1c; color: #fff; }
</style>
