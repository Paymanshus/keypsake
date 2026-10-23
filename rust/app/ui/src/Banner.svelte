<script>
  // PermissionBanner on macOS. Windows needs no permission, so this only shows when capture couldn't start.
  let { error } = $props();
</script>

<div class="banner">
  <div class="title medium">keypsake can't see what you type right now</div>
  <div class="sub soft">{error} Clipboard history still works. Quitting and opening keypsake again usually fixes this.</div>
</div>

<style>
  .banner { padding: 12px 20px; background: color-mix(in srgb, var(--carbon) 7%, transparent); border-bottom: 1px solid var(--rule); display: flex; flex-direction: column; gap: 3px; }
  .title { font-size: 12.5px; }
  .sub { font-size: 11.5px; }
</style>
