/* Password gate + shared chrome for DEKRA study app.
 * Default password hash = SHA-256("copilot-erfurt") — override via localStorage key
 * fahrpruefung.passHash if you rotate (see SERVER.credentials.local.md).
 */
(function () {
  const AUTH_KEY = "fahrpruefung.authed";
  const PASS_HASH_KEY = "fahrpruefung.passHash";
  const DEFAULT_HASH =
    "9d1696e75f3b1a4d148880c5bb63515c76741aae39ae568139894f5bca14e447";

  const PATH = "/fahrpruefung/";

  /* Pure JS SHA-256 — works on plain HTTP (VPS has no HTTPS yet). */
  function sha256sync(ascii) {
    function rotr(n, x) {
      return (x >>> n) | (x << (32 - n));
    }
    function toHex(i) {
      return ("00000000" + (i >>> 0).toString(16)).slice(-8);
    }
    const K = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];
    const H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    const bytes = [];
    for (let i = 0; i < ascii.length; i++) bytes.push(ascii.charCodeAt(i) & 0xff);
    bytes.push(0x80);
    while (bytes.length % 64 !== 56) bytes.push(0);
    const bitLen = ascii.length * 8;
    for (let i = 7; i >= 0; i--) bytes.push(Math.floor(bitLen / Math.pow(2, 8 * i)) & 0xff);
    for (let offset = 0; offset < bytes.length; offset += 64) {
      const w = new Array(64);
      for (let i = 0; i < 16; i++) {
        w[i] =
          (bytes[offset + i * 4] << 24) |
          (bytes[offset + i * 4 + 1] << 16) |
          (bytes[offset + i * 4 + 2] << 8) |
          bytes[offset + i * 4 + 3];
      }
      for (let i = 16; i < 64; i++) {
        const s0 = rotr(7, w[i - 15]) ^ rotr(18, w[i - 15]) ^ (w[i - 15] >>> 3);
        const s1 = rotr(17, w[i - 2]) ^ rotr(19, w[i - 2]) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      let [a, b, c, d, e, f, g, h] = H;
      for (let i = 0; i < 64; i++) {
        const S1 = rotr(6, e) ^ rotr(11, e) ^ rotr(25, e);
        const ch = (e & f) ^ (~e & g);
        const t1 = (h + S1 + ch + K[i] + w[i]) | 0;
        const S0 = rotr(2, a) ^ rotr(13, a) ^ rotr(22, a);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (S0 + maj) | 0;
        h = g;
        g = f;
        f = e;
        e = (d + t1) | 0;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) | 0;
      }
      H[0] = (H[0] + a) | 0;
      H[1] = (H[1] + b) | 0;
      H[2] = (H[2] + c) | 0;
      H[3] = (H[3] + d) | 0;
      H[4] = (H[4] + e) | 0;
      H[5] = (H[5] + f) | 0;
      H[6] = (H[6] + g) | 0;
      H[7] = (H[7] + h) | 0;
    }
    return H.map(toHex).join("");
  }

  async function sha256(text) {
    if (window.crypto && crypto.subtle && location.protocol === "https:") {
      const data = new TextEncoder().encode(text);
      const buf = await crypto.subtle.digest("SHA-256", data);
      return Array.from(new Uint8Array(buf))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    }
    return sha256sync(text);
  }

  function expectedHash() {
    return localStorage.getItem(PASS_HASH_KEY) || DEFAULT_HASH;
  }

  function isAuthed() {
    return sessionStorage.getItem(AUTH_KEY) === "1";
  }

  function setAuthed(ok) {
    if (ok) sessionStorage.setItem(AUTH_KEY, "1");
    else sessionStorage.removeItem(AUTH_KEY);
  }

  function base() {
    // support both /fahrpruefung/ and file:// relative
    const m = location.pathname.match(/^(.*\/fahrpruefung\/)/);
    return m ? m[1] : "./";
  }

  function logoSrc() {
    return base() + "assets/logo.svg";
  }

  function renderGate() {
    if (document.getElementById("gate")) return;
    const el = document.createElement("div");
    el.id = "gate";
    el.innerHTML = `
      <form class="gate-card" id="gate-form" autocomplete="current-password">
        <img src="${logoSrc()}" alt="copilot." width="180" height="36"/>
        <h1>DEKRA · Praktische Prüfung</h1>
        <p>Stichworte für den Prüfer — nur mit Passwort</p>
        <label for="gate-pass">Passwort</label>
        <input id="gate-pass" name="password" type="password" required autofocus placeholder="••••••••"/>
        <div class="gate-err" id="gate-err" aria-live="polite"></div>
        <button class="btn btn-primary" type="submit">App öffnen</button>
      </form>
    `;
    document.body.prepend(el);
    document.getElementById("gate-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const pass = document.getElementById("gate-pass").value.trim();
      const err = document.getElementById("gate-err");
      err.textContent = "";
      try {
        const hash = await sha256(pass);
        if (hash === expectedHash()) {
          setAuthed(true);
          el.hidden = true;
          document.body.classList.add("authed");
          document.dispatchEvent(new CustomEvent("fahr:ready"));
        } else {
          err.textContent = "Falsches Passwort.";
        }
      } catch (ex) {
        err.textContent = "Login fehlgeschlagen (Browser braucht HTTPS oder localhost).";
      }
    });
  }

  function ensureAuth() {
    if (isAuthed()) {
      document.body.classList.add("authed");
      return true;
    }
    renderGate();
    return false;
  }

  function logout() {
    setAuthed(false);
    location.reload();
  }

  function header(active) {
    return `
      <header class="app-header">
        <a class="brand" href="${base()}">
          <img src="${logoSrc()}" alt="copilot." width="120" height="24"/>
          <div class="brand-text">
            <strong>Fahrprüfung</strong>
            <span>Klasse B · PKW</span>
          </div>
        </a>
        <div class="header-actions">
          <span class="pill">DEKRA</span>
          <button type="button" class="btn btn-ghost" id="logout-btn" style="padding:0.45rem 0.8rem;font-size:0.8rem">Logout</button>
        </div>
      </header>
    `;
  }

  function bottomNav(active) {
    const items = [
      { id: "home", href: base(), label: "Home", ico: "⌂" },
      { id: "sheet", href: base() + "sheet.html", label: "Blatt", ico: "▤" },
      { id: "review", href: base() + "review.html", label: "Lernen", ico: "☰" },
      { id: "train", href: base() + "train.html", label: "Karten", ico: "▭" },
      { id: "quiz", href: base() + "quiz.html", label: "Quiz", ico: "?" },
      { id: "plakette", href: base() + "plakette.html", label: "HU", ico: "◉" }
    ];
    return `
      <nav class="bottom-nav bottom-nav-6" aria-label="App-Navigation">
        ${items
          .map(
            (it) => `
          <a href="${it.href}" class="${it.id === active ? "active" : ""}">
            <span class="nav-ico" aria-hidden="true">${it.ico}</span>
            ${it.label}
          </a>`
          )
          .join("")}
      </nav>
    `;
  }

  function mountChrome(active) {
    if (!document.body.classList.contains("authed")) return;
    if (!document.querySelector(".app-header")) {
      document.body.insertAdjacentHTML("afterbegin", header(active));
      document.getElementById("logout-btn")?.addEventListener("click", logout);
    }
    if (!document.querySelector(".bottom-nav")) {
      document.body.insertAdjacentHTML("beforeend", bottomNav(active));
    }
  }

  function shuffle(arr) {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  /* ── Home ── */
  function renderHome() {
    const root = qs("#app");
    if (!root || !window.FAHR) return;
    const { meta, rules, sections } = FAHR;
    root.innerHTML = `
      <div class="wrap">
        <section class="hero">
          <h1>${meta.title}</h1>
          <p>${meta.subtitle} — trainiere die Stichworte, die du dem Prüfer zeigst und sagst.</p>
        </section>
        <div class="rules">
          ${rules
            .map(
              (r) => `
            <div class="rule">
              <div class="label">${r.label}</div>
              <div class="text">${r.text}</div>
            </div>`
            )
            .join("")}
        </div>
        <a class="mode-card mode-card-featured" href="${base()}sheet.html">
          <div class="ico">▤</div>
          <h2>Stichworte-Blatt</h2>
          <p>Das Copilot-Cheat-Sheet fürs Handy — gleiche Stichworte wie auf dem Papier.</p>
        </a>
        <div class="modes modes-4">
          <a class="mode-card" href="${base()}review.html">
            <div class="ico">01</div>
            <h2>Kapitel lernen</h2>
            <p>Alle Themen mit Keywords und Safe Answers.</p>
          </a>
          <a class="mode-card" href="${base()}train.html">
            <div class="ico">▭</div>
            <h2>Karteikarten</h2>
            <p>Tippen → Antwort. Deutsch trainieren wie in der Prüfung.</p>
          </a>
          <a class="mode-card" href="${base()}quiz.html">
            <div class="ico">?</div>
            <h2>Quiz</h2>
            <p>A–D Zufall — Safe Answers und Begriffe prüfen.</p>
          </a>
          <a class="mode-card" href="${base()}plakette.html">
            <div class="ico">◉</div>
            <h2>Prüfplakette</h2>
            <p>Interaktiv: Monat, Jahr und Farbe ablesen üben.</p>
          </a>
        </div>
        <h2 style="font-size:1.05rem;margin:0 0 0.65rem;letter-spacing:-0.02em">Kapitel</h2>
        <div class="section-grid">
          ${sections
            .map(
              (s) => `
            <a class="sec-card" href="${base()}review.html#${s.id}">
              <div class="sec-num">${s.num}</div>
              <div>
                <h3>${s.title}</h3>
                <p>${s.summary}</p>
              </div>
            </a>`
            )
            .join("")}
        </div>
        <p class="footer-note">${meta.school} · ${meta.address} · ${sections.length} Kapitel · build 20260822c</p>
      </div>
    `;
  }

  /* ── Review ── */
  function renderReview() {
    const root = qs("#app");
    if (!root || !window.FAHR) return;
    const hash = (location.hash || "").replace("#", "");
    root.innerHTML = `
      <div class="wrap">
        <section class="hero">
          <h1>Kapitel lernen</h1>
          <p>Stichworte (gelb) laut sagen — kurz, klar, zeigen + sagen.</p>
        </section>
        <div class="filter-row" id="sec-filters"></div>
        <div id="sec-panels"></div>
        <p class="footer-note">Gelb = Keyword für den Prüfer</p>
      </div>
    `;
    const filters = qs("#sec-filters");
    const panels = qs("#sec-panels");
    filters.innerHTML =
      `<button type="button" class="chip active" data-id="all">Alle</button>` +
      FAHR.sections
        .map((s) => `<button type="button" class="chip" data-id="${s.id}">${s.num}</button>`)
        .join("");

    function paint(filterId) {
      filters.querySelectorAll(".chip").forEach((c) => {
        c.classList.toggle("active", c.dataset.id === filterId);
      });
      const list =
        filterId === "all" ? FAHR.sections : FAHR.sections.filter((s) => s.id === filterId);
      panels.innerHTML = list
        .map((s) => {
          const points = s.points
            .map((p) => {
              const term = p.kw ? `<span class="kw">${p.de}</span>` : p.de;
              const dot = p.dash ? `<span class="dash-dot dash-${p.dash}" aria-hidden="true"></span>` : "";
              return `<li>
                <div class="point-term">${dot}${term}</div>
                <div class="point-tip">${p.tip}</div>
              </li>`;
            })
            .join("");
          return `
            <section class="panel" id="${s.id}">
              <h2><span style="color:var(--orange);font-family:var(--mono);font-size:0.85rem;margin-right:0.4rem">${s.num}</span>${s.title}</h2>
              <p class="lede">${s.summary}</p>
              <ul class="point-list">${points}</ul>
              ${
                s.say
                  ? `<div class="say-box"><div class="label">Safe Answer</div><div class="line">„${s.say}“</div></div>`
                  : ""
              }
            </section>`;
        })
        .join("");
      if (filterId !== "all") {
        qs("#" + filterId)?.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }

    filters.addEventListener("click", (e) => {
      const btn = e.target.closest(".chip");
      if (!btn) return;
      paint(btn.dataset.id);
      history.replaceState(null, "", btn.dataset.id === "all" ? location.pathname : "#" + btn.dataset.id);
    });

    paint(hash && FAHR.sections.some((s) => s.id === hash) ? hash : "all");
    if (hash) {
      setTimeout(() => qs("#" + hash)?.scrollIntoView({ behavior: "smooth", block: "start" }), 50);
    }
  }

  /* ── Train (flashcards) ── */
  function renderTrain() {
    const root = qs("#app");
    if (!root || !window.FAHR) return;
    let cards = shuffle(FAHR.buildCards());
    let i = 0;
    let revealed = false;

    root.innerHTML = `
      <div class="wrap">
        <section class="hero">
          <h1>Karteikarten</h1>
          <p>Vorderseite laut sagen, dann tippen für die Antwort.</p>
        </section>
        <div class="toolbar">
          <div class="meta-line" id="train-meta"></div>
          <button type="button" class="btn btn-ghost" id="train-shuffle" style="padding:0.45rem 0.85rem;font-size:0.85rem">Mischen</button>
        </div>
        <div class="progress"><span id="train-bar"></span></div>
        <div class="flash" id="flash" tabindex="0" role="button" aria-label="Karte umdrehen">
          <div class="flash-inner" id="flash-inner"></div>
        </div>
        <div class="controls">
          <button type="button" class="btn btn-ghost" id="train-prev">← Zurück</button>
          <button type="button" class="btn btn-soft" id="train-flip">Umdrehen</button>
          <button type="button" class="btn btn-primary" id="train-next" style="width:auto;min-width:8rem">Weiter →</button>
        </div>
      </div>
    `;

    function paint() {
      const c = cards[i];
      qs("#train-meta").textContent = `${i + 1} / ${cards.length} · ${c.section}`;
      qs("#train-bar").style.width = ((i + 1) / cards.length) * 100 + "%";
      qs("#flash-inner").innerHTML = revealed
        ? `<div class="eyebrow">${c.section}${c.safe ? " · Safe Answer" : ""}</div>
           <div class="front">${c.front}</div>
           <div class="back">${c.back}</div>
           <div class="hint">Tippen für nächste / vorherige mit Tasten → ←</div>`
        : `<div class="eyebrow">${c.section}${c.safe ? " · Safe Answer" : ""}</div>
           <div class="front">${c.kw ? `<span class="kw">${c.front}</span>` : c.front}</div>
           <div class="hint">Tippen zum Aufdecken</div>`;
    }

    function flip() {
      revealed = !revealed;
      paint();
    }
    function next() {
      i = (i + 1) % cards.length;
      revealed = false;
      paint();
    }
    function prev() {
      i = (i - 1 + cards.length) % cards.length;
      revealed = false;
      paint();
    }

    qs("#flash").addEventListener("click", flip);
    qs("#train-flip").addEventListener("click", flip);
    qs("#train-next").addEventListener("click", next);
    qs("#train-prev").addEventListener("click", prev);
    qs("#train-shuffle").addEventListener("click", () => {
      cards = shuffle(cards);
      i = 0;
      revealed = false;
      paint();
    });
    document.addEventListener("keydown", (e) => {
      if (!document.body.classList.contains("authed")) return;
      if (e.key === " " || e.key === "Enter") {
        e.preventDefault();
        flip();
      }
      if (e.key === "ArrowRight") next();
      if (e.key === "ArrowLeft") prev();
    });
    paint();
  }

  /* ── Quiz (A–D, correct index randomized each question) ── */
  function renderQuiz() {
    const root = qs("#app");
    if (!root || !window.FAHR) return;
    const LETTERS = ["A", "B", "C", "D"];
    let deck = shuffle(FAHR.buildQuiz());
    let i = 0;
    let score = 0;
    let locked = false;
    let correctIndex = 0;

    root.innerHTML = `
      <div class="wrap">
        <section class="hero">
          <h1>Quiz</h1>
          <p>Antworten A–D werden jedes Mal neu gemischt.</p>
        </section>
        <div class="toolbar">
          <div class="meta-line" id="quiz-meta"></div>
          <div class="score" id="quiz-score">0 richtig</div>
        </div>
        <div class="progress"><span id="quiz-bar"></span></div>
        <div class="panel">
          <div class="quiz-q" id="quiz-q"></div>
          <div class="choices" id="quiz-choices"></div>
        </div>
        <div class="controls">
          <button type="button" class="btn btn-primary" id="quiz-next" style="width:auto;min-width:9rem" hidden>Weiter →</button>
          <button type="button" class="btn btn-ghost" id="quiz-restart" style="padding:0.55rem 1rem;font-size:0.9rem" hidden>Nochmal</button>
        </div>
      </div>
    `;

    function buildOptions(item) {
      const wrong = shuffle(item.wrong.slice()).slice(0, 3);
      const opts = shuffle([{ text: item.correct, ok: true }].concat(wrong.map((t) => ({ text: t, ok: false }))));
      return opts;
    }

    function paint() {
      locked = false;
      const item = deck[i];
      const opts = buildOptions(item);
      correctIndex = opts.findIndex((o) => o.ok);
      qs("#quiz-meta").textContent = `${i + 1} / ${deck.length} · ${item.section}`;
      qs("#quiz-bar").style.width = (i / deck.length) * 100 + "%";
      qs("#quiz-score").textContent = score + " richtig";
      qs("#quiz-q").textContent = item.q;
      qs("#quiz-next").hidden = true;
      qs("#quiz-restart").hidden = true;

      const box = qs("#quiz-choices");
      box.innerHTML = opts
        .map(
          (o, idx) => `
          <button type="button" class="choice" data-idx="${idx}">
            <span class="choice-letter">${LETTERS[idx]}</span>
            <span class="choice-text">${o.text}</span>
          </button>`
        )
        .join("");

      box.querySelectorAll(".choice").forEach((btn) => {
        btn.addEventListener("click", () => {
          if (locked) return;
          locked = true;
          const idx = Number(btn.dataset.idx);
          const ok = idx === correctIndex;
          if (ok) score += 1;
          box.querySelectorAll(".choice").forEach((b) => {
            b.disabled = true;
            const bi = Number(b.dataset.idx);
            if (bi === correctIndex) b.classList.add("correct");
            else if (b === btn && !ok) b.classList.add("wrong");
          });
          qs("#quiz-score").textContent = score + " richtig";
          qs("#quiz-next").hidden = false;
          if (i === deck.length - 1) qs("#quiz-next").textContent = "Ergebnis";
          else qs("#quiz-next").textContent = "Weiter →";
        });
      });
    }

    qs("#quiz-next").addEventListener("click", () => {
      if (i >= deck.length - 1) {
        qs("#quiz-q").textContent = `Fertig — ${score} von ${deck.length} richtig.`;
        qs("#quiz-choices").innerHTML = "";
        qs("#quiz-bar").style.width = "100%";
        qs("#quiz-next").hidden = true;
        qs("#quiz-restart").hidden = false;
        return;
      }
      i += 1;
      paint();
    });

    qs("#quiz-restart").addEventListener("click", () => {
      deck = shuffle(FAHR.buildQuiz());
      i = 0;
      score = 0;
      qs("#quiz-next").textContent = "Weiter →";
      paint();
    });

    paint();
  }

  /* ── Prüfplakette interactive demo ── */
  function monthName(m) {
    return [
      "",
      "Januar",
      "Februar",
      "März",
      "April",
      "Mai",
      "Juni",
      "Juli",
      "August",
      "September",
      "Oktober",
      "November",
      "Dezember"
    ][m];
  }

  function plaketteMeta(year) {
    const list = FAHR.plaketteColors;
    let row = list.find((c) => c.year === year);
    if (!row) {
      const base = list[0];
      const idx = ((year - base.year) % 6 + 6) % 6;
      row = {
        year,
        color: list[idx].color,
        name: list[idx].name,
        hexYear: String(year).slice(-2)
      };
    }
    return row;
  }

  function plaketteSvg(month, year) {
    const meta = plaketteMeta(year);
    const yy = meta.hexYear;
    const cx = 100;
    const cy = 100;
    const rOuter = 88;
    const rMid = 58;
    const rInner = 36;
    // Month number sits at top (12 o'clock). Ring numbers are rotated so `month` is on top.
    let nums = "";
    for (let m = 1; m <= 12; m++) {
      const angle = ((m - month) / 12) * Math.PI * 2 - Math.PI / 2;
      const x = cx + Math.cos(angle) * 73;
      const y = cy + Math.sin(angle) * 73;
      nums += `<text x="${x.toFixed(1)}" y="${y.toFixed(1)}" text-anchor="middle" dominant-baseline="central" font-size="11" font-weight="700" fill="#111">${m}</text>`;
    }
    // Black bars near top (month marker visible from distance)
    const bar = `
      <path d="M ${cx - 22} ${cy - rOuter + 2} A ${rOuter - 2} ${rOuter - 2} 0 0 1 ${cx + 22} ${cy - rOuter + 2}
               L ${cx + 14} ${cy - rOuter + 18} A ${rOuter - 18} ${rOuter - 18} 0 0 0 ${cx - 14} ${cy - rOuter + 18} Z"
            fill="#111"/>`;
    return `
      <svg class="plakette-svg" viewBox="0 0 200 200" role="img" aria-label="Prüfplakette ${month}/${year}">
        <circle cx="${cx}" cy="${cy}" r="${rOuter}" fill="${meta.color}"/>
        <circle cx="${cx}" cy="${cy}" r="${rMid}" fill="#f4f4f4"/>
        <circle cx="${cx}" cy="${cy}" r="${rInner}" fill="${meta.color}"/>
        ${bar}
        ${nums}
        <text x="${cx}" y="${cy + 2}" text-anchor="middle" dominant-baseline="central"
              font-size="28" font-weight="800" fill="#fff">${yy}</text>
      </svg>`;
  }

  function renderPlakette() {
    const root = qs("#app");
    if (!root) return;
    if (!window.FAHR || !FAHR.plaketteColors) {
      root.innerHTML = `<div class="wrap"><div class="panel"><h2>Plakette konnte nicht laden</h2>
        <p class="lede">Alte Datei im Cache. Hard-Refresh: iPhone Safari tippe die URL-Leiste → neu laden, oder Cache leeren.</p>
        <p><a class="btn btn-primary" href="${base()}?v=20260822c" style="width:auto;display:inline-flex">Zur Startseite</a></p>
      </div></div>`;
      return;
    }
    let month = 9;
    let year = 2026;
    let mode = "learn"; // learn | quiz
    let quiz = null;

    root.innerHTML = `
      <div class="wrap">
        <section class="hero">
          <h1>Prüfplakette ablesen</h1>
          <p>Oben = Monat · Mitte = Jahr · Farbe = Jahr. Interaktiv üben.</p>
        </section>

        <div class="filter-row" id="plak-modes">
          <button type="button" class="chip active" data-mode="learn">Lernen</button>
          <button type="button" class="chip" data-mode="quiz">Üben</button>
        </div>

        <div class="plak-layout">
          <div class="panel plak-visual">
            <div class="plate">
              <div class="plate-inner">
                <span class="plate-eu">D</span>
                <span class="plate-text">EF AB 123</span>
                <div id="plak-mount" class="plak-mount"></div>
              </div>
            </div>
            <p class="plak-readout" id="plak-readout"></p>
            <div class="say-box" style="margin-top:0.85rem">
              <div class="label">Safe Answer</div>
              <div class="line">„Oben = Monat (bis Monatsende), Mitte = Jahr.“</div>
            </div>
          </div>

          <div class="panel" id="plak-controls"></div>
        </div>

        <div class="panel">
          <h2>So liest du den Kreis</h2>
          <ul class="point-list">
            <li>
              <div class="point-term"><span class="kw">Monat</span></div>
              <div class="point-tip">Die Zahl, die <strong>oben</strong> steht (12-Uhr-Position).</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Jahr</span></div>
              <div class="point-tip">Die Zahl in der <strong>Mitte</strong> (z.&nbsp;B. 26 → 2026).</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Farbe</span></div>
              <div class="point-tip">Kodiert ebenfalls das Jahr (Blau 2026, Gelb 2027, …).</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Schwarze Balken</span></div>
              <div class="point-tip">Von weitem sichtbar — zeigen denselben Monat wie „oben“.</div>
            </li>
          </ul>
          <div class="ref-photo">
            <img src="assets/plakette-ref.png"
                 alt="Beispiel HU-Prüfplakette: Monat oben, Jahr in der Mitte"
                 loading="lazy"/>
            <p class="ref-cap">Beispiel: Zahl oben = Monat · Mitte = Jahr · Farbe = Jahr</p>
          </div>
        </div>

        <div class="panel">
          <h2>Frist &amp; Regeln (wichtig)</h2>
          <ul class="point-list">
            <li>
              <div class="point-term"><span class="kw">Was heißt „September“?</span></div>
              <div class="point-tip">Nicht nur Anfang oder Mitte — die HU ist im <strong>ganzen September</strong> fällig und muss <strong>spätestens am Monatsende</strong> (30.9.) erledigt sein.</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Keine +2-Monate-Kulanz</span></div>
              <div class="point-tip">Die 2 Monate sind <strong>kein</strong> Extra-Zeitraum für eine pünktliche HU. Ab dem 1. des Folgemonats gilt die HU bereits als überzogen.</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Überziehung ≤ 2 Monate</span></div>
              <div class="point-tip">Meist noch <strong>kein</strong> Verwarnungsgeld bei Kontrolle; normale HU möglich.</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Überziehung &gt; 2–4 Monate</span></div>
              <div class="point-tip"><strong>15 €</strong> · und erweiterte HU (+ ca. 20&nbsp;% Gebühr).</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Überziehung &gt; 4–8 Monate</span></div>
              <div class="point-tip"><strong>25 €</strong>.</div>
            </li>
            <li>
              <div class="point-term"><span class="kw">Überziehung &gt; 8 Monate</span></div>
              <div class="point-tip"><strong>60 €</strong> und <strong>1 Punkt</strong> in Flensburg.</div>
            </li>
          </ul>
          <div class="say-box" style="margin-top:1rem">
            <div class="label">Für den Prüfer (kurz)</div>
            <div class="line">„Oben = Monat — HU bis Monatsende. Mitte = Jahr.“</div>
          </div>
        </div>
      </div>
    `;

    function paintVisual() {
      qs("#plak-mount").innerHTML = plaketteSvg(month, year);
      const meta = plaketteMeta(year);
      qs("#plak-readout").innerHTML = mode === "learn"
        ? `<strong>${monthName(month)} ${year}</strong> · Farbe <span class="kw">${meta.name}</span>`
        : quiz && quiz.revealed
          ? `<strong>${monthName(quiz.month)} ${quiz.year}</strong> · ${plaketteMeta(quiz.year).name}`
          : `Was ist Monat und Jahr?`;
    }

    function paintControls() {
      const box = qs("#plak-controls");
      if (mode === "learn") {
        box.innerHTML = `
          <h2>Einstellen</h2>
          <p class="lede">Drehe Monat/Jahr — die Plakette aktualisiert sich live.</p>
          <label class="field-label">Monat (oben)</label>
          <input type="range" id="plak-month" min="1" max="12" value="${month}"/>
          <div class="field-value" id="plak-month-val">${month} · ${monthName(month)}</div>
          <label class="field-label">Jahr (Mitte)</label>
          <div class="year-row" id="plak-years"></div>
          <p class="lede" style="margin-top:1rem">Tipp für den Prüfer: zeigen + kurz sagen.</p>
        `;
        const years = FAHR.plaketteColors;
        qs("#plak-years").innerHTML = years
          .map(
            (y) => `
            <button type="button" class="year-chip ${y.year === year ? "active" : ""}" data-y="${y.year}"
              style="--yc:${y.color}">${y.year}<small>${y.name}</small></button>`
          )
          .join("");
        qs("#plak-month").addEventListener("input", (e) => {
          month = Number(e.target.value);
          qs("#plak-month-val").textContent = `${month} · ${monthName(month)}`;
          paintVisual();
        });
        qs("#plak-years").addEventListener("click", (e) => {
          const btn = e.target.closest(".year-chip");
          if (!btn) return;
          year = Number(btn.dataset.y);
          paintControls();
          paintVisual();
        });
      } else {
        if (!quiz) {
          quiz = {
            month: 1 + Math.floor(Math.random() * 12),
            year: FAHR.plaketteColors[Math.floor(Math.random() * FAHR.plaketteColors.length)].year,
            revealed: false
          };
          month = quiz.month;
          year = quiz.year;
        }
        const optsM = shuffle(
          [quiz.month]
            .concat(shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].filter((m) => m !== quiz.month)).slice(0, 3))
        );
        const optsY = shuffle(
          [quiz.year].concat(
            shuffle(FAHR.plaketteColors.map((c) => c.year).filter((y) => y !== quiz.year)).slice(0, 3)
          )
        );
        box.innerHTML = `
          <h2>Ablesen üben</h2>
          <p class="lede">Lies die Plakette links ab — dann tippe Monat und Jahr.</p>
          <div class="quiz-q" style="font-size:1.05rem">Welcher Monat steht oben?</div>
          <div class="choices" id="plak-m-choices">
            ${optsM
              .map(
                (m, idx) => `
              <button type="button" class="choice" data-m="${m}">
                <span class="choice-letter">${["A", "B", "C", "D"][idx]}</span>
                <span class="choice-text">${m} · ${monthName(m)}</span>
              </button>`
              )
              .join("")}
          </div>
          <div class="quiz-q" style="font-size:1.05rem;margin-top:1rem">Welches Jahr steht in der Mitte?</div>
          <div class="choices" id="plak-y-choices">
            ${optsY
              .map(
                (y, idx) => `
              <button type="button" class="choice" data-y="${y}">
                <span class="choice-letter">${["A", "B", "C", "D"][idx]}</span>
                <span class="choice-text">${y}</span>
              </button>`
              )
              .join("")}
          </div>
          <div class="controls" style="margin-top:1rem">
            <button type="button" class="btn btn-soft" id="plak-reveal" style="width:auto">Auflösen</button>
            <button type="button" class="btn btn-primary" id="plak-next" style="width:auto">Neue Plakette</button>
          </div>
          <p class="lede" id="plak-quiz-msg" style="margin-top:0.75rem"></p>
        `;

        let pickedM = null;
        let pickedY = null;
        function check() {
          if (pickedM == null || pickedY == null) return;
          const ok = pickedM === quiz.month && pickedY === quiz.year;
          qs("#plak-quiz-msg").textContent = ok
            ? `Richtig — ${monthName(quiz.month)} ${quiz.year}.`
            : `Noch nicht — Safe Answer: Oben = Monat, Mitte = Jahr.`;
          qs("#plak-quiz-msg").style.color = ok ? "var(--ok)" : "var(--bad)";
        }
        qs("#plak-m-choices").addEventListener("click", (e) => {
          const btn = e.target.closest(".choice");
          if (!btn || quiz.revealed) return;
          pickedM = Number(btn.dataset.m);
          qs("#plak-m-choices").querySelectorAll(".choice").forEach((b) => b.classList.remove("picked"));
          btn.classList.add("picked");
          check();
        });
        qs("#plak-y-choices").addEventListener("click", (e) => {
          const btn = e.target.closest(".choice");
          if (!btn || quiz.revealed) return;
          pickedY = Number(btn.dataset.y);
          qs("#plak-y-choices").querySelectorAll(".choice").forEach((b) => b.classList.remove("picked"));
          btn.classList.add("picked");
          check();
        });
        qs("#plak-reveal").addEventListener("click", () => {
          quiz.revealed = true;
          qs("#plak-m-choices").querySelectorAll(".choice").forEach((b) => {
            b.disabled = true;
            if (Number(b.dataset.m) === quiz.month) b.classList.add("correct");
            else if (b.classList.contains("picked")) b.classList.add("wrong");
          });
          qs("#plak-y-choices").querySelectorAll(".choice").forEach((b) => {
            b.disabled = true;
            if (Number(b.dataset.y) === quiz.year) b.classList.add("correct");
            else if (b.classList.contains("picked")) b.classList.add("wrong");
          });
          qs("#plak-quiz-msg").textContent = `${monthName(quiz.month)} ${quiz.year} · ${plaketteMeta(quiz.year).name}`;
          qs("#plak-quiz-msg").style.color = "var(--ink)";
          paintVisual();
        });
        qs("#plak-next").addEventListener("click", () => {
          quiz = null;
          paintControls();
          paintVisual();
        });
      }
    }

    qs("#plak-modes").addEventListener("click", (e) => {
      const btn = e.target.closest(".chip");
      if (!btn) return;
      mode = btn.dataset.mode;
      quiz = null;
      qs("#plak-modes").querySelectorAll(".chip").forEach((c) => c.classList.toggle("active", c === btn));
      paintControls();
      paintVisual();
    });

    paintControls();
    paintVisual();
  }

  /* ── Cheat sheet (Copilot one-pager, mobile) ── */
  function renderSheet() {
    const root = qs("#app");
    if (!root || !window.FAHR) return;
    const { meta, rules, sections } = FAHR;
    const jump = sections
      .map((s) => `<a class="sheet-jump-item" href="#sheet-${s.id}">${s.num}</a>`)
      .join("");
    const cards = sections
      .map((s) => {
        const rows = s.points
          .map((p) => {
            const term = p.kw ? `<span class="kw">${p.de}</span>` : p.de;
            const dot = p.dash ? `<span class="dash-dot dash-${p.dash}" aria-hidden="true"></span>` : "";
            return `<li><div class="sheet-term">${dot}${term}</div><div class="sheet-tip">${p.tip}</div></li>`;
          })
          .join("");
        return `
          <article class="sheet-card" id="sheet-${s.id}">
            <h2><span>${s.num}</span>${s.title}</h2>
            <ul>${rows}</ul>
            ${s.say ? `<div class="sheet-say">„${s.say}“</div>` : ""}
          </article>`;
      })
      .join("");
    root.innerHTML = `
      <div class="wrap wrap-sheet">
        <div class="sheet">
          <header class="sheet-banner">
            <img src="${logoSrc()}" alt="copilot." width="140" height="28"/>
            <div class="sheet-banner-text">
              <div class="sheet-kicker">${meta.title}</div>
              <div class="sheet-sub">${meta.subtitle}</div>
            </div>
            <div class="sheet-class">${meta.classLabel}</div>
          </header>
          <div class="sheet-rules">
            ${rules
              .map(
                (r) => `
              <div class="sheet-rule">
                <div class="label">${r.label}</div>
                <div class="text">${r.text}</div>
              </div>`
              )
              .join("")}
          </div>
          <nav class="sheet-jump" aria-label="Kapitel">${jump}</nav>
          <div class="sheet-grid">${cards}</div>
          <p class="sheet-foot">${meta.school} · ${meta.address} · Gelb = Stichwort</p>
          <details class="sheet-original">
            <summary>Originalfoto vom Papier-Blatt</summary>
            <img src="${base()}assets/copilot-stichworte.jpg" alt="Original Copilot Stichworte-Blatt"/>
          </details>
        </div>
      </div>
    `;
  }

  window.FahrApp = {
    ensureAuth,
    mountChrome,
    renderHome,
    renderReview,
    renderTrain,
    renderQuiz,
    renderPlakette,
    renderSheet,
    logout,
    sha256,
    setPasswordHash: async (plain) => {
      const h = await sha256(plain);
      localStorage.setItem(PASS_HASH_KEY, h);
      return h;
    }
  };

  document.addEventListener("DOMContentLoaded", () => {
    const page = document.body.dataset.page || "home";
    const ok = ensureAuth();
    const boot = () => {
      mountChrome(page);
      if (page === "home") renderHome();
      if (page === "review") renderReview();
      if (page === "train") renderTrain();
      if (page === "quiz") renderQuiz();
      if (page === "plakette") renderPlakette();
      if (page === "sheet") renderSheet();
    };
    if (ok) boot();
    else document.addEventListener("fahr:ready", boot, { once: true });
  });
})();
