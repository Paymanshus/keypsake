<script>
  import { app, copy, onNav } from "./state.svelte.js";
  import { call, contextMenu } from "./api.js";
  import EmptyNote from "./EmptyNote.svelte";
  import SessionDetail from "./SessionDetail.svelte";
  import SessionRow from "./SessionRow.svelte";

  let selection = $state(null);
  let snaps = $state([]);
  let version = $state(null);
  let listEl = $state();

  const items = $derived.by(() => {
    const q = app.query.trim().toLowerCase();
    if (!q) return app.sessions;
    return app.sessions.filter((s) =>
      [s.text, s.domain ?? s.app, s.window, s.app].some((v) => v.toLowerCase().includes(q)),
    );
  });
  const current = $derived(items.find((s) => s.id === selection) ?? items[0]);

  // Reload versions when the selected box or its latest version changes.
  $effect(() => {
    const item = current;
    void item?.updated;
    if (!item) {
      snaps = [];
      return;
    }
    let live = true;
    call("snapshots", { session: item.id }).then(({ snaps: fresh, defaultVersion }) => {
      if (!live) return;
      if (fresh[0]?.id !== snaps[0]?.id || !fresh.some((s) => s.id === version)) version = defaultVersion;
      snaps = fresh;
    });
    return () => (live = false);
  });

  function copyVersion(item) {
    const text = snaps.find((s) => s.id === version)?.text ?? item.text;
    copy(text, item.id);
  }

  function select(id) {
    selection = id;
    queueMicrotask(() => listEl?.querySelector(`[data-id="${id}"]`)?.scrollIntoView({ block: "nearest" }));
  }

  $effect(() =>
    onNav((what) => {
      if (app.tab !== "typed" || !current) return;
      const i = items.indexOf(current);
      if (what === "up") select(items[Math.max(i - 1, 0)].id);
      else if (what === "down") select(items[Math.min(i + 1, items.length - 1)].id);
      else if (what === "enter") copyVersion(current);
      else if (what === "delete") call("delete_session", { id: current.id });
    }),
  );

  function menu(e, item) {
    e.preventDefault();
    contextMenu([
      ["Copy latest text", () => copy(item.text, item.id)],
      ["Delete", () => call("delete_session", { id: item.id })],
    ]);
  }
</script>

{#if app.sessions.length === 0}
  <EmptyNote line="Type anywhere. It shows up here."
    sub="Whatever you type into a text box, in any app, is kept for {app.status?.prefs.retentionDays ?? 30} days." />
{:else if items.length === 0}
  <EmptyNote line="Nothing matches “{app.query}”." />
{:else}
  <div class="split">
    <div class="list" bind:this={listEl} role="listbox">
      {#each items as item (item.id)}
        <div data-id={item.id}>
          <SessionRow {item} selected={item.id === current?.id} copied={app.flash === item.id}
            onselect={() => (selection = item.id)} oncopy={() => copy(item.text, item.id)} onmenu={(e) => menu(e, item)} />
        </div>
      {/each}
    </div>
    {#if current}
      <SessionDetail item={current} {snaps} {version} onversion={(v) => (version = v)}
        copied={app.flash === current.id} oncopy={() => copyVersion(current)} />
    {/if}
  </div>
{/if}

<style>
  .split { flex: 1; min-height: 0; display: flex; }
  .list { width: 310px; flex: none; overflow-y: auto; border-right: 1px solid var(--rule); }
</style>
