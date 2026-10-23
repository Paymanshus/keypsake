<script>
  // Text length per version over time. Cliff versions (right before text vanished) show in amber.
  import { short, count } from "./stamp.js";
  let { snaps, selected, onpick } = $props();
  const top = $derived(Math.max(...snaps.map((s) => s.length), 1));

  function color(s) {
    if (s.id === selected) return s.cliff ? "var(--cliff)" : "var(--ink)";
    return s.cliff ? "color-mix(in srgb, var(--cliff) 55%, transparent)" : "var(--ghost)";
  }
</script>

<div class="ribbon">
  {#each snaps.slice(-30) as s (s.id)}
    <button title="{short(s.created)}  ·  {count(s.length)}" onclick={() => onpick(s.id)}>
      <span style:height="{Math.max(4, (30 * s.length) / top)}px" style:background={color(s)}></span>
    </button>
  {/each}
</div>

<style>
  .ribbon { display: flex; align-items: flex-end; height: 34px; }
  button { width: 11px; height: 34px; display: flex; align-items: flex-end; justify-content: center; cursor: pointer; }
  span { width: 7px; border-radius: 1.5px; }
</style>
