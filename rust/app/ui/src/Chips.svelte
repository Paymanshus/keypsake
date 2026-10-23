<script>
  let { options, value, onpick } = $props();
</script>

<div class="chips">
  {#each options as [v, label]}
    <button class="mono medium" class:on={v === value} onclick={() => onpick(v)}>{label}</button>
  {/each}
</div>

<style>
  .chips { display: inline-flex; gap: 2px; padding: 2px; border-radius: 7px; background: var(--wash); }
  button { font-size: 10.5px; padding: 0 9px; height: 24px; border-radius: 5px; color: var(--ink-soft); cursor: pointer; }
  button.on { background: var(--carbon); color: var(--ground); }
</style>
