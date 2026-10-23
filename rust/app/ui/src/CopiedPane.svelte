<script>
  import { app, copy, onNav } from "./state.svelte.js";
  import { call, contextMenu } from "./api.js";
  import ClipRow from "./ClipRow.svelte";
  import EmptyNote from "./EmptyNote.svelte";

  let selection = $state(null);
  let listEl = $state();

  const items = $derived.by(() => {
    const q = app.query.trim().toLowerCase();
    if (!q) return app.clips;
    return app.clips.filter((c) => c.text.toLowerCase().includes(q) || c.app.toLowerCase().includes(q) || (c.domain ?? "").includes(q));
  });
  const current = $derived(items.find((c) => c.id === selection) ?? items[0]);

  function select(id) {
    selection = id;
    queueMicrotask(() => listEl?.querySelector(`[data-id="${id}"]`)?.scrollIntoView({ block: "nearest" }));
  }

  $effect(() =>
    onNav((what) => {
      if (app.tab !== "copied" || !current) return;
      const i = items.indexOf(current);
      if (what === "up") select(items[Math.max(i - 1, 0)].id);
      else if (what === "down") select(items[Math.min(i + 1, items.length - 1)].id);
      else if (what === "enter") copy(current.text, current.id);
      else if (what === "delete") call("delete_clip", { id: current.id });
      else if (what.startsWith?.("num") && items[+what.slice(3)]) {
        const c = items[+what.slice(3)];
        copy(c.text, c.id);
        select(c.id);
      }
    }),
  );

  function menu(e, clip) {
    e.preventDefault();
    contextMenu([
      ["Copy", () => copy(clip.text, clip.id)],
      ["Delete", () => call("delete_clip", { id: clip.id })],
    ]);
  }
</script>

{#if app.clips.length === 0}
  <EmptyNote line="Copy anything. It lands here."
    sub="Your last {app.status?.prefs.clipLimit ?? 50} copies are kept. Passwords from password managers are skipped." />
{:else if items.length === 0}
  <EmptyNote line="Nothing matches “{app.query}”." />
{:else}
  <div class="list" bind:this={listEl} role="listbox">
    {#each items as clip, i (clip.id)}
      <div data-id={clip.id}>
        <ClipRow {clip} index={i} selected={clip.id === current?.id} copied={app.flash === clip.id}
          onclick={() => { selection = clip.id; copy(clip.text, clip.id); }} onmenu={(e) => menu(e, clip)} />
      </div>
    {/each}
  </div>
{/if}

<style>
  .list { flex: 1; overflow-y: auto; }
</style>
