<script>
  // Click, then press the new shortcut. Esc cancels. Needs Ctrl, Alt or Win (Shift alone isn't enough).
  let { value, onchange } = $props();
  let recording = $state(false);
  const display = (s) => s.replace("Super", "Win");

  function key(e) {
    if (!recording) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.key === "Escape") return (recording = false);
    if (!(e.ctrlKey || e.altKey || e.metaKey)) return;
    let k = null;
    if (/^Key[A-Z]$/.test(e.code)) k = e.code.slice(3);
    else if (/^Digit[0-9]$/.test(e.code)) k = e.code.slice(5);
    else if (/^F([1-9]|1[0-2])$/.test(e.code)) k = e.code;
    else if (e.code === "Space") k = "Space";
    if (!k) return;
    const mods = [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Super"].filter(Boolean);
    onchange([...mods, k].join("+"));
    recording = false;
  }
</script>

<svelte:window onkeydown={key} />

<button class="rec mono medium" class:recording onclick={() => (recording = !recording)} onblur={() => (recording = false)}>
  {recording ? "Press keys…" : display(value)}
</button>

<style>
  .rec { font-size: 11px; padding: 0 10px; min-width: 70px; min-height: 26px; border-radius: 7px; background: var(--wash); cursor: pointer; }
  .rec.recording { color: var(--carbon); background: color-mix(in srgb, var(--carbon) 14%, transparent); }
</style>
