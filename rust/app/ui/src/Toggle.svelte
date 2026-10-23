<script>
  let { on, onchange, label } = $props();
</script>

<button class="toggle" class:on role="switch" aria-checked={on} aria-label={label} onclick={() => onchange(!on)}><span></span></button>

<style>
  .toggle { width: 40px; height: 20px; border-radius: 10px; border: 1px solid var(--ink-soft); position: relative; cursor: pointer; flex: none; }
  .toggle span { position: absolute; top: 3px; left: 4px; width: 12px; height: 12px; border-radius: 50%; background: var(--ink-soft); transition: left 0.12s ease-out; }
  .toggle.on { background: var(--carbon); border-color: var(--carbon); }
  .toggle.on span { left: 23px; background: var(--ground); }
</style>
