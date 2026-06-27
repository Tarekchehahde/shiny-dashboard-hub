const DOCS = [
  { id: "overview", title: "Overview", group: "Server" },
  { id: "dashboards", title: "All dashboards", group: "Server" },
  { id: "thueringen", title: "Thüringen demos", group: "Server" },
  { id: "monitoring", title: "Monitoring & ops", group: "Server" },
  { id: "infrastructure", title: "Infrastructure", group: "Server" },
  { id: "ml", title: "Machine learning", group: "Development" },
  { id: "reference-verification", title: "Reference verification tool", group: "Methods" },
];

const navEl = document.getElementById("doc-nav");
const contentEl = document.getElementById("doc-content");
const privacyBanner = document.getElementById("privacy-banner");

function currentDocId() {
  const params = new URLSearchParams(window.location.search);
  const id = params.get("doc") || "overview";
  return DOCS.some((d) => d.id === id) ? id : "overview";
}

function buildNav(activeId) {
  let lastGroup = "";
  navEl.innerHTML = "";
  DOCS.forEach((doc) => {
    if (doc.group !== lastGroup) {
      const g = document.createElement("div");
      g.className = "nav-group";
      g.textContent = doc.group;
      navEl.appendChild(g);
      lastGroup = doc.group;
    }
    const a = document.createElement("a");
    a.href = `?doc=${doc.id}`;
    a.textContent = doc.title;
    if (doc.id === activeId) a.classList.add("active");
    navEl.appendChild(a);
  });
}

async function loadDoc(id) {
  buildNav(id);
  contentEl.innerHTML = '<p class="loading">Loading…</p>';
  privacyBanner.hidden = id !== "reference-verification";
  document.title = `${DOCS.find((d) => d.id === id)?.title || "Docs"} — MaStR Documentation`;

  try {
    const res = await fetch(`content/${id}.md`, { cache: "no-cache" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const md = await res.text();
    contentEl.innerHTML = marked.parse(md, { gfm: true, breaks: false });
    contentEl.querySelectorAll("pre code").forEach((block) => {
      if (!block.classList.contains("language-mermaid")) return;
      const parent = block.parentElement;
      const div = document.createElement("div");
      div.className = "mermaid";
      div.textContent = block.textContent;
      parent.replaceWith(div);
    });
    if (window.mermaid) {
      mermaid.run({ nodes: contentEl.querySelectorAll(".mermaid") });
    }
  } catch (err) {
    contentEl.innerHTML = `<p class="error">Could not load documentation: ${err.message}</p>`;
  }
}

window.addEventListener("popstate", () => loadDoc(currentDocId()));
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("#doc-nav").forEach(() => {});
  loadDoc(currentDocId());
  navEl.addEventListener("click", (e) => {
    const a = e.target.closest("a");
    if (!a) return;
    e.preventDefault();
    const url = new URL(a.href, window.location.origin);
    history.pushState({}, "", url.pathname + url.search);
    loadDoc(currentDocId());
  });
});
