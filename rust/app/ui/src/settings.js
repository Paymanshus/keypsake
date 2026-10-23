import "./theme.css";
import { mount } from "svelte";
import Settings from "./Settings.svelte";
import { load } from "./state.svelte.js";

document.addEventListener("contextmenu", (e) => e.preventDefault());
load().then(() => mount(Settings, { target: document.getElementById("app") }));
