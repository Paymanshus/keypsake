<script>
  // MainView in Views.swift.
  import { app, nav } from "./state.svelte.js";
  import { call, currentWindow } from "./api.js";
  import Banner from "./Banner.svelte";
  import CopiedPane from "./CopiedPane.svelte";
  import Header from "./Header.svelte";
  import TypedPane from "./TypedPane.svelte";

  const typing = (t) => t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement;

  function key(e) {
    if (e.ctrlKey && !e.altKey && !e.shiftKey) {
      if (e.key === "[") app.tab = "typed";
      else if (e.key === "]") app.tab = "copied";
      else if (e.key === "f") app.focusSearch++;
      else if (e.key === ",") call("open_settings");
      else if (e.key === "Delete") nav("delete");
      else if (app.tab === "copied" && /^[1-9]$/.test(e.key)) nav("num" + (+e.key - 1));
      else return;
      e.preventDefault();
    } else if (e.key === "Escape") {
      if (app.query) app.query = "";
      else currentWindow().then((w) => w?.hide());
      e.preventDefault();
    } else if (!typing(e.target) && !e.ctrlKey && !e.altKey) {
      // Not in the search box: arrows and Enter still move through the list.
      if (e.key === "ArrowUp") nav("up");
      else if (e.key === "ArrowDown") nav("down");
      else if (e.key === "Enter") nav("enter");
      else return;
      e.preventDefault();
    }
  }
</script>

<svelte:window onkeydown={key} />

<main>
  <Header />
  {#if app.tab === "typed"}
    {#if app.status?.typingError}<Banner error={app.status.typingError} />{/if}
    <TypedPane />
  {:else}
    <CopiedPane />
  {/if}
</main>

<style>
  main { height: 100%; display: flex; flex-direction: column; }
  main > :global(header) { border-bottom: 1px solid var(--rule); }
</style>
