<script>
  import { app, nav, setPrefs } from "./state.svelte.js";
  import { call } from "./api.js";
  import Icon from "./Icon.svelte";
  import WindowControls from "./WindowControls.svelte";

  let search = $state();
  $effect(() => {
    if (app.focusSearch) search?.focus();
  });
  const paused = $derived(app.status?.prefs.paused ?? false);
  const pauseKey = $derived(app.status?.prefs.shortcutPause.replace("Super", "Win") ?? "");

  function key(e) {
    if (e.key === "ArrowUp") nav("up");
    else if (e.key === "ArrowDown") nav("down");
    else if (e.key === "Enter") nav("enter");
    else return;
    e.preventDefault();
  }
</script>

<!-- Empty header space drags the window (double-click maximizes). Everything else stays put. -->
<header data-tauri-drag-region>
  <span class="display wordmark" data-tauri-drag-region>keypsake</span>
  {#each [["Typed", "typed"], ["Copied", "copied"]] as [label, t]}
    <button class="tab medium" class:on={app.tab === t} onclick={() => (app.tab = t)}>{label}</button>
  {/each}
  <span class="spacer" data-tauri-drag-region></span>
  <label class="search">
    <span class="faint"><Icon name="search" size={11} stroke={1.8} /></span>
    <input bind:this={search} bind:value={app.query} onkeydown={key} spellcheck="false"
      placeholder={app.tab === "typed" ? "Search typed text" : "Search copies"} />
    {#if app.query}
      <button class="faint clear" title="Clear" onclick={() => (app.query = "")}><Icon name="clear" size={11} /></button>
    {/if}
  </label>
  <button class="quiet rec" title="{paused ? 'Resume' : 'Pause'} recording ({pauseKey})" onclick={() => setPrefs({ paused: !paused })}>
    <span class="dot" class:paused></span>
    <span class="mono" class:soft={!paused} class:faint={paused}>{paused ? "paused" : "rec"}</span>
  </button>
  <button class="quiet bare gear soft" title="Settings (Ctrl+,)" onclick={() => call("open_settings")}><Icon name="gear" size={14} stroke={1.3} /></button>
  <WindowControls />
</header>

<style>
  header { height: 52px; flex: none; display: flex; align-items: center; padding-left: 20px; }
  .wordmark { font-size: 22px; margin-right: 28px; }
  .tab { font-size: 12.5px; height: 100%; color: var(--ink-faint); cursor: pointer; box-shadow: inset 0 -2px 0 transparent; }
  .tab + .tab { margin-left: 18px; }
  .tab.on { color: var(--ink); box-shadow: inset 0 -2px 0 var(--carbon); }
  .spacer { flex: 1; min-width: 16px; align-self: stretch; }
  .search { display: flex; align-items: center; gap: 7px; width: 230px; height: 28px; padding: 0 10px; border-radius: 7px; background: var(--wash); }
  .search input { flex: 1; min-width: 0; border: 0; outline: 0; background: none; font-size: 12.5px; }
  .search input::placeholder { color: var(--ink-faint); }
  .search span, .clear { display: flex; }
  .clear { cursor: pointer; }
  .rec { margin-left: 14px; min-width: 48px; justify-content: flex-start; gap: 6px; }
  .rec .mono { font-size: 10.5px; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--carbon); border: 1.2px solid var(--carbon); }
  .dot.paused { background: none; border-color: var(--ink-faint); }
  .gear { margin: 0 8px 0 4px; }
</style>
