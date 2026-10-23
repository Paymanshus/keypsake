<script>
  // Windows caption buttons; the macOS app has traffic lights on the left instead.
  import { currentWindow } from "./api.js";
  import Icon from "./Icon.svelte";
  let { minimize = true, maximize = true } = $props();
  let maximized = $state(false);

  $effect(() => {
    let off;
    currentWindow().then(async (w) => {
      if (!w) return;
      maximized = await w.isMaximized();
      off = await w.onResized(async () => (maximized = await w.isMaximized()));
    });
    return () => off?.();
  });

  const act = (f) => currentWindow().then((w) => w && f(w));
</script>

<div class="controls">
  {#if minimize}
    <button title="Minimize" onclick={() => act((w) => w.minimize())}><Icon name="minimize" size={10} stroke={1.1} /></button>
  {/if}
  {#if maximize}
    <button title={maximized ? "Restore" : "Maximize"} onclick={() => act((w) => w.toggleMaximize())}>
      <Icon name={maximized ? "restore" : "maximize"} size={10} stroke={1.1} />
    </button>
  {/if}
  <button class="close" title="Close" onclick={() => act((w) => w.close())}><Icon name="close" size={10} stroke={1.1} /></button>
</div>

<style>
  .controls { display: flex; align-self: stretch; }
  button { width: 46px; display: flex; align-items: center; justify-content: center; color: var(--ink-soft); }
  button:hover { background: var(--wash); color: var(--ink); }
  .close:hover { background: #c42b1c; color: #fff; }
</style>
