<script>
  // Stand-ins for the SF Symbols the macOS app uses (Lucide-style strokes).
  let { name, size = 13, stroke = 1.6 } = $props();
  const paths = {
    search: "M11 11l3.5 3.5M7 12.5A5.5 5.5 0 1 0 7 1.5a5.5 5.5 0 0 0 0 11z",
    gear: "M8 10.2a2.2 2.2 0 1 0 0-4.4 2.2 2.2 0 0 0 0 4.4zM13 8.6l1.3 1-1.3 2.3-1.6-.5a5 5 0 0 1-1.2.7L9.9 14H7.3L7 12.1a5 5 0 0 1-1.2-.7l-1.6.5-1.3-2.3 1.3-1a5 5 0 0 1 0-1.4l-1.3-1 1.3-2.3 1.6.5A5 5 0 0 1 7 3.9L7.3 2h2.6l.3 1.9a5 5 0 0 1 1.2.7l1.6-.5 1.3 2.3-1.3 1a5 5 0 0 1 0 1.2z",
    copy: "M5.5 5.5h7v8h-7zM3.5 10.5v-8h7",
    check: "M3 8.5l3 3 7-7",
    left: "M10 3L5 8l5 5",
    right: "M6 3l5 5-5 5",
    clear: "M8 15A7 7 0 1 0 8 1a7 7 0 0 0 0 14zM5.5 5.5l5 5M10.5 5.5l-5 5",
    minimize: "M3 8h10",
    maximize: "M3.5 3.5h9v9h-9z",
    restore: "M3.5 5.5h7v7h-7zM5.5 5.5v-2h7v7h-2",
    close: "M3.5 3.5l9 9M12.5 3.5l-9 9",
  };
</script>

<svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width={stroke}
  stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  <path d={paths[name]} />
</svg>
