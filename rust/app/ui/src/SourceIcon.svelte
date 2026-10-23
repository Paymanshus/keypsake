<script>
  // Favicon when there's a site, else the app's own icon, else a quiet square.
  import { call } from "./api.js";
  let { bundle = null, domain = null, size = 18 } = $props();
  const cache = (globalThis.__icons ??= new Map());

  function load(kind, key) {
    const k = kind + ":" + key;
    if (!cache.has(k)) cache.set(k, call(kind === "site" ? "favicon" : "app_icon", kind === "site" ? { domain: key } : { bundle: key }).catch(() => null));
    return cache.get(k);
  }

  let src = $state(null);
  let fav = $state(false);
  $effect(() => {
    let live = true;
    src = null;
    (async () => {
      const site = domain ? await load("site", domain) : null;
      const appIcon = !site && bundle ? await load("app", bundle) : null;
      if (live) {
        src = site ?? appIcon;
        fav = !!site;
      }
    })();
    return () => (live = false);
  });
</script>

{#if src}
  <img {src} alt="" style:width="{size}px" style:height="{size}px" style:border-radius={fav ? "3.5px" : "0"} draggable="false" />
{:else}
  <span class="blank" style:width="{size}px" style:height="{size}px"></span>
{/if}

<style>
  img { display: block; object-fit: contain; flex: none; }
  .blank { display: block; flex: none; border-radius: 4px; background: var(--wash); }
</style>
