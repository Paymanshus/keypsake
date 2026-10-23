<script>
  import { short, oneLine } from "./stamp.js";
  import Icon from "./Icon.svelte";
  import SourceIcon from "./SourceIcon.svelte";
  let { item, selected, copied, oncopy, onselect, onmenu } = $props();
  const title = $derived(item.domain ?? item.app);
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div class="row" class:selected role="option" tabindex="-1" aria-selected={selected} onclick={onselect} oncontextmenu={onmenu}>
  <div class="icon"><SourceIcon bundle={item.bundle} domain={item.domain} size={18} /></div>
  <div class="body">
    <div class="top">
      <span class="display title one-line">{title}</span>
      {#if copied}
        <button class="quiet copy mono carbon" onclick={(e) => { e.stopPropagation(); oncopy(); }}><Icon name="check" size={10} />Copied</button>
      {:else}
        <span class="mono faint stamp">{short(item.updated)}</span>
        <button class="quiet copy mono soft hover" title="Copy latest text" onclick={(e) => { e.stopPropagation(); oncopy(); }}><Icon name="copy" size={10} />Copy</button>
      {/if}
    </div>
    {#if item.window && item.window !== title}
      <div class="window faint one-line">{item.window}</div>
    {/if}
    <div class="preview soft">{oneLine(item.text, 400)}</div>
  </div>
</div>

<style>
  .row { display: flex; gap: 11px; padding: 12px 14px 12px 16px; position: relative; }
  .row::after { content: ""; position: absolute; left: 45px; right: 0; bottom: 0; height: 1px; background: var(--rule-half); }
  .row.selected { background: var(--wash); box-shadow: inset 2px 0 0 var(--carbon); }
  .icon { padding-top: 1px; }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .top { height: 20px; display: flex; align-items: center; gap: 8px; }
  .title { flex: 1; font-size: 16.5px; }
  .stamp { font-size: 10px; }
  .copy { font-size: 10px; min-height: 20px; height: 20px; display: none; }
  .carbon { color: var(--carbon); display: inline-flex; }
  .row:hover .hover { display: inline-flex; }
  .row:hover .stamp { display: none; }
  .window { font-size: 11px; }
  .preview { font-size: 12px; line-height: 16px; padding-top: 2px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
</style>
