<script>
  import { app, setPrefs } from "./state.svelte.js";
  import { call } from "./api.js";
  import { short, count } from "./stamp.js";
  import Chips from "./Chips.svelte";
  import Icon from "./Icon.svelte";
  import Ribbon from "./Ribbon.svelte";
  import SourceIcon from "./SourceIcon.svelte";

  let { item, snaps, version, onversion, copied, oncopy } = $props();
  const showChanges = $derived(app.status?.prefs.showChanges ?? true);
  const title = $derived(item.domain ?? item.app);
  const index = $derived(Math.max(0, snaps.findIndex((s) => s.id === version)));
  const current = $derived(snaps.find((s) => s.id === version) ?? snaps.at(-1));
  const previous = $derived(current && index > 0 ? snaps[index - 1] : null);

  let diff = $state(null);
  $effect(() => {
    const c = current, p = previous;
    diff = null;
    if (!c || !p) return;
    let live = true;
    call("compare", { old: p.text, new: c.text }).then((r) => live && (diff = { id: c.id, result: r }));
    return () => (live = false);
  });
  const changes = $derived(showChanges && previous && diff?.id === current?.id ? diff.result : null);

  const meta = $derived.by(() => {
    const parts = [];
    if (item.window && item.window !== title) parts.push(item.window);
    if (item.domain) parts.push(item.app);
    parts.push(short(current?.created ?? item.updated));
    parts.push(count(current?.length ?? item.text.length));
    return parts.join("  ·  ");
  });
  const versionLabel = $derived(
    !current ? "" : snaps.length === 1 ? "1 version" : `version ${index + 1} of ${snaps.length}  ·  ${short(current.created)}`,
  );
  const cliffLabel = $derived.by(() => {
    if (!current?.cliff) return null;
    if (index + 1 < snaps.length) return `dropped to ${count(snaps[index + 1].length)} right after this`;
    return "box was cleared right after this";
  });

  let textEl = $state();
  let lastText;
  $effect(() => {
    const t = current?.text;
    if (t !== lastText && textEl) textEl.scrollTop = 0;
    lastText = t;
  });

  function step(d) {
    const t = index + d;
    if (t >= 0 && t < snaps.length) onversion(snaps[t].id);
  }
</script>

<div class="detail">
  <div class="head">
    <div class="titlebar">
      <SourceIcon bundle={item.bundle} domain={item.domain} size={22} />
      <span class="display title one-line">{title}</span>
      <button class="quiet copy medium" class:copied title="Copy this version (Enter)" onclick={oncopy}>
        <Icon name={copied ? "check" : "copy"} size={12} />{copied ? "Copied" : "Copy"}
      </button>
    </div>
    <div class="mono faint meta one-line">{meta}</div>
  </div>

  {#if previous}
    <div class="changes">
      <Chips options={[[0, "Text"], [1, "Changes"]]} value={showChanges ? 1 : 0} onpick={(v) => setPrefs({ showChanges: v === 1 })} />
      {#if showChanges && diff?.id === current?.id && diff.result}
        <span class="soft summary one-line">{diff.result.summary}</span>
        <span class="legend"><span class="added">added</span><span class="removed">removed</span></span>
      {:else if showChanges && diff?.id === current?.id}
        <span class="faint summary">Too long to compare word by word</span>
      {/if}
    </div>
  {/if}

  <div class="text" bind:this={textEl} data-native-menu>
    {#if changes}
      {#each changes.spans as s}<span class={s.kind}>{s.text}</span>{/each}
    {:else}
      {current?.text ?? item.text}
    {/if}
  </div>

  <div class="foot">
    <div class="versions">
      <button class="quiet step" disabled={index <= 0} class:off={index <= 0} title="Older version" onclick={() => step(-1)}><Icon name="left" size={11} stroke={2} /></button>
      <Ribbon {snaps} selected={current?.id} onpick={onversion} />
      <button class="quiet step" disabled={index >= snaps.length - 1} class:off={index >= snaps.length - 1} title="Newer version" onclick={() => step(1)}><Icon name="right" size={11} stroke={2} /></button>
    </div>
    <div class="labels mono">
      <span class="soft">{versionLabel}</span>
      {#if cliffLabel}<span class="cliff">{cliffLabel}</span>{/if}
    </div>
    <span class="grow"></span>
    <button class="pill prominent" title="Enter" onclick={oncopy}>{copied ? "Copied" : "Copy this version"}</button>
  </div>
</div>

<style>
  .detail { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .head { padding: 20px 26px 16px; display: flex; flex-direction: column; gap: 7px; border-bottom: 1px solid var(--rule); }
  .titlebar { display: flex; align-items: center; gap: 10px; }
  .title { flex: 1; font-size: 26px; }
  .copy { font-size: 12px; min-height: 28px; margin-left: 12px; }
  .copy.copied { color: var(--carbon); }
  .meta { font-size: 10.5px; white-space: pre; }
  .changes { height: 40px; flex: none; padding: 0 26px; display: flex; align-items: center; gap: 14px; border-bottom: 1px solid var(--rule-half); }
  .summary { flex: 1; font-size: 11.5px; }
  .legend { display: flex; gap: 10px; font-size: 11px; }
  .legend .added { padding: 0 3px; }
  .text {
    flex: 1; overflow-y: auto; padding: 20px 22px; font-size: 14px; line-height: 25px;
    white-space: pre-wrap; overflow-wrap: anywhere; user-select: text; cursor: text;
  }
  .added { background: color-mix(in srgb, var(--carbon) 18%, transparent); }
  .removed { color: var(--cliff-text); text-decoration: line-through; text-decoration-color: var(--cliff-text); }
  .foot { height: 68px; flex: none; padding: 0 26px; display: flex; align-items: center; gap: 18px; border-top: 1px solid var(--rule); }
  .versions { display: flex; align-items: center; gap: 6px; }
  .step { min-height: 28px; min-width: 28px; color: var(--ink); }
  .step.off { border-color: transparent; color: color-mix(in srgb, var(--ink-faint) 50%, transparent); }
  .labels { display: flex; flex-direction: column; gap: 3px; font-size: 10.5px; white-space: pre; }
  .cliff { color: var(--cliff); }
  .grow { flex: 1; min-width: 8px; }
</style>
