// The Beady website's script: search, the Copy button, and the "on this page" highlight.
// Everything here is an enhancement — the pages read and navigate without it.

// ---------- Search ----------
// Full-text search over the guide, entirely in the browser. The index is one JSON file that
// Hugo writes at build time (layouts/home.json); it's fetched the first time the box opens.

const dialog = document.querySelector("[data-search]");
if (dialog && typeof dialog.showModal === "function") {
  const input = dialog.querySelector("input");
  const list = dialog.querySelector("[data-search-results]");
  const status = dialog.querySelector("[data-search-status]");
  const openers = document.querySelectorAll("[data-search-open]");
  let entries = null;
  let results = [];
  let active = 0;

  // "Café" and "cafe" should find each other; so should "⌘P" typed as "cmd p" not, sadly.
  const fold = (text) => text.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

  const load = async () => {
    if (entries) return;
    try {
      const response = await fetch(dialog.dataset.search);
      entries = (await response.json()).map((entry) => ({
        ...entry,
        foldedTitle: fold(entry.title),
        foldedPage: fold(entry.page),
        foldedText: fold(entry.text),
      }));
    } catch {
      entries = [];
      status.textContent = "Search couldn't load its index. Try reloading the page.";
    }
  };

  // Every word typed has to appear somewhere in the entry. A hit in the heading counts for
  // more than one in the page's title, which counts for more than one in the body; a word
  // that starts a word beats one found in the middle of another.
  const score = (entry, terms) => {
    let total = 0;
    for (const term of terms) {
      let best = 0;
      for (const [field, weight] of [[entry.foldedTitle, 12], [entry.foldedPage, 5], [entry.foldedText, 1]]) {
        const at = field.indexOf(term);
        if (at < 0) continue;
        const startsWord = at === 0 || /[^a-z0-9]/.test(field[at - 1]);
        best = Math.max(best, weight * (startsWord ? 2 : 1));
      }
      if (best === 0) return 0;
      total += best;
    }
    // A section's own heading matching is better than its page's intro matching the same way.
    return total + (entry.url.includes("#") ? 0 : 0.5);
  };

  // The stretch of body text around the first word found, with the words marked.
  const excerpt = (entry, terms) => {
    const fragment = document.createDocumentFragment();
    const text = entry.text;
    const folded = entry.foldedText;
    let first = -1;
    for (const term of terms) {
      const at = folded.indexOf(term);
      if (at >= 0 && (first < 0 || at < first)) first = at;
    }
    let start = Math.max(0, (first < 0 ? 0 : first) - 50);
    if (start > 0) start = text.indexOf(" ", start) + 1;
    const end = Math.min(text.length, start + 170);
    const slice = text.slice(start, end);
    const foldedSlice = fold(slice);
    // Folding can't change a string's length here (it only strips combining marks that NFD
    // split out), but if it ever did, marking would land in the wrong place: show it plain.
    if (foldedSlice.length !== slice.length) {
      fragment.append((start > 0 ? "… " : "") + slice + (end < text.length ? " …" : ""));
      return fragment;
    }
    const marks = [];
    for (const term of terms) {
      for (let at = foldedSlice.indexOf(term); at >= 0; at = foldedSlice.indexOf(term, at + term.length)) {
        marks.push([at, at + term.length]);
      }
    }
    marks.sort((a, b) => a[0] - b[0]);
    let cursor = 0;
    if (start > 0) fragment.append("… ");
    for (const [from, to] of marks) {
      if (from < cursor) continue;
      fragment.append(slice.slice(cursor, from));
      const mark = document.createElement("mark");
      mark.textContent = slice.slice(from, to);
      fragment.append(mark);
      cursor = to;
    }
    fragment.append(slice.slice(cursor));
    if (end < text.length) fragment.append(" …");
    return fragment;
  };

  const highlight = () => {
    list.querySelectorAll("a").forEach((link, index) => {
      const on = index === active;
      link.classList.toggle("is-active", on);
      link.setAttribute("aria-selected", on ? "true" : "false");
      if (on) link.scrollIntoView({ block: "nearest" });
    });
  };

  const render = () => {
    const terms = fold(input.value).split(/\s+/).filter(Boolean);
    list.replaceChildren();
    active = 0;
    if (!entries || terms.length === 0) {
      results = [];
      status.textContent = entries && entries.length ? "Type to search the guide." : status.textContent;
      return;
    }
    results = entries
      .map((entry) => ({ entry, score: score(entry, terms) }))
      .filter((result) => result.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 12);
    status.textContent = results.length === 0
      ? `Nothing in the guide matches “${input.value.trim()}”.`
      : `${results.length} result${results.length === 1 ? "" : "s"}`;
    for (const { entry } of results) {
      const item = document.createElement("li");
      const link = document.createElement("a");
      link.href = entry.url;
      link.setAttribute("role", "option");
      const title = document.createElement("strong");
      title.textContent = entry.title;
      link.append(title);
      if (entry.page !== entry.title) {
        const page = document.createElement("span");
        page.className = "search__page";
        page.textContent = entry.page;
        link.append(page);
      }
      const body = document.createElement("span");
      body.className = "search__excerpt";
      body.append(excerpt(entry, terms));
      link.append(body);
      item.append(link);
      list.append(item);
    }
    highlight();
  };

  const open = async () => {
    if (dialog.open) return;
    dialog.showModal();
    input.select();
    await load();
    render();
  };

  for (const opener of openers) {
    opener.hidden = false;
    opener.addEventListener("click", open);
  }
  input.addEventListener("input", render);
  input.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (results.length === 0) return;
      active = (active + (event.key === "ArrowDown" ? 1 : -1) + results.length) % results.length;
      highlight();
    } else if (event.key === "Enter") {
      const link = list.querySelectorAll("a")[active];
      if (link) {
        event.preventDefault();
        dialog.close();
        window.location.href = link.href;
      }
    }
  });
  // A result on the page you're already reading only moves the scroll position.
  list.addEventListener("click", (event) => { if (event.target.closest("a")) dialog.close(); });
  // A click on the dimmed page behind the box closes it.
  dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });

  document.addEventListener("keydown", (event) => {
    const typing = event.target instanceof HTMLElement
      && (event.target.isContentEditable || /^(input|textarea|select)$/i.test(event.target.tagName));
    const slash = event.key === "/" && !typing && !event.metaKey && !event.ctrlKey && !event.altKey;
    const commandK = event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey);
    if (slash || commandK) {
      event.preventDefault();
      open();
    }
  });
}

// ---------- Screenshots, larger ----------
// A screenshot in the guide is a window drawn at half its size or less. Clicking it shows the
// whole thing over the page; Escape or another click puts it away.
const zoomLinks = document.querySelectorAll("a[data-zoom]");
if (zoomLinks.length && typeof HTMLDialogElement === "function") {
  const viewer = document.createElement("dialog");
  viewer.className = "zoom";
  viewer.setAttribute("aria-label", "Screenshot");
  const image = document.createElement("img");
  viewer.append(image);
  document.body.append(viewer);
  viewer.addEventListener("click", () => viewer.close());
  for (const link of zoomLinks) {
    link.addEventListener("click", (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey) return;
      event.preventDefault();
      image.src = link.href;
      image.alt = link.querySelector("img")?.alt ?? "";
      viewer.showModal();
    });
  }
}

// ---------- Copy buttons ----------
for (const button of document.querySelectorAll("[data-copy]")) {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      const label = button.textContent;
      button.textContent = "Copied";
      setTimeout(() => { button.textContent = label; }, 1600);
    } catch { /* clipboard refused; the text is selectable */ }
  });
}

// ---------- On this page ----------
// Marks the outline's link for the section being read.
const outline = document.querySelector("[data-outline]");
if (outline && "IntersectionObserver" in window) {
  const links = new Map();
  for (const link of outline.querySelectorAll("a[href^='#']")) {
    const heading = document.getElementById(decodeURIComponent(link.hash.slice(1)));
    if (heading) links.set(heading, link);
  }
  const visible = new Set();
  const observer = new IntersectionObserver((changes) => {
    for (const change of changes) {
      if (change.isIntersecting) visible.add(change.target); else visible.delete(change.target);
    }
    // The first heading on screen; if none is, keep whichever was marked.
    const current = [...links.keys()].find((heading) => visible.has(heading));
    if (!current) return;
    for (const link of links.values()) link.removeAttribute("aria-current");
    links.get(current).setAttribute("aria-current", "true");
  }, { rootMargin: "-72px 0px -60% 0px" });
  for (const heading of links.keys()) observer.observe(heading);
}
