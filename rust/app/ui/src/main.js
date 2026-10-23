import "./theme.css";
import { mount } from "svelte";
import App from "./App.svelte";
import { load } from "./state.svelte.js";

// Selected text keeps the webview's own Copy menu; everywhere else right-click is ours (or nothing).
document.addEventListener("contextmenu", (e) => {
  if (!e.target.closest?.("[data-native-menu]")) e.preventDefault();
});
load().then(() => mount(App, { target: document.getElementById("app") }));
