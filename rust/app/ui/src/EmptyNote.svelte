<script>
  let { line, sub = null } = $props();
</script>

<div class="wrap">
  <div class="note">
    <div class="display line">{line}</div>
    {#if sub}<div class="soft sub">{sub}</div>{/if}
  </div>
</div>

<style>
  .wrap { flex: 1; display: flex; align-items: center; justify-content: center; }
  .note { max-width: 380px; text-align: center; display: flex; flex-direction: column; gap: 8px; }
  .line { font-size: 24px; }
  .sub { font-size: 12px; line-height: 1.4; }
</style>
