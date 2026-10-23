<script>
  import { short, count, oneLine } from "./stamp.js";
  import SourceIcon from "./SourceIcon.svelte";
  let { clip, index, selected, copied, onclick, onmenu } = $props();
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div class="row" class:selected class:copied role="option" tabindex="-1" aria-selected={selected} {onclick} oncontextmenu={onmenu}>
  <div class="icon"><SourceIcon bundle={clip.bundle} domain={clip.domain} size={16} /></div>
  <div class="body">
    <div class="text" class:open={selected}>{selected ? clip.text : oneLine(clip.text, 300)}</div>
    <div class="mono meta" class:faint={!copied}>
      {copied ? "Copied" : `${clip.domain ?? clip.app}  ·  ${short(clip.created)}  ·  ${count([...clip.text].length)}`}
    </div>
  </div>
  {#if index < 9}<span class="mono faint key">Ctrl+{index + 1}</span>{/if}
</div>

<style>
  .row { display: flex; gap: 12px; padding: 11px 18px 11px 20px; position: relative; transition: background 0.18s ease-out; }
  .row::after { content: ""; position: absolute; left: 48px; right: 0; bottom: 0; height: 1px; background: var(--rule-half); }
  .row.selected { background: var(--wash); box-shadow: inset 2px 0 0 var(--carbon); }
  .row.copied { background: color-mix(in srgb, var(--carbon) 12%, transparent); }
  .icon { padding-top: 1px; }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .text { font-size: 13px; line-height: 17px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .text.open { white-space: pre-wrap; overflow-wrap: anywhere; display: -webkit-box; -webkit-line-clamp: 10; -webkit-box-orient: vertical; }
  .meta { font-size: 10px; color: var(--carbon); white-space: pre; overflow: hidden; text-overflow: ellipsis; }
  .meta.faint { color: var(--ink-faint); }
  .key { font-size: 10px; padding-top: 2px; }
</style>
