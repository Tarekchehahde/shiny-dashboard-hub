(() => {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ========== Career journey ========== */
  const journey = document.querySelector("[data-journey]");
  if (journey) {
    const track = journey.querySelector(".journey-track");
    const fill = journey.querySelector(".journey-fill");
    const nodes = [...journey.querySelectorAll(".journey-node")];
    const filters = [...journey.querySelectorAll("[data-filter]")];
    const hint = journey.querySelector(".journey-hint");

    const setOpen = (node, open) => {
      node.classList.toggle("is-open", open);
      const btn = node.querySelector(".journey-head");
      if (btn) btn.setAttribute("aria-expanded", open ? "true" : "false");
    };

    nodes.forEach((node) => {
      const btn = node.querySelector(".journey-head");
      if (!btn) return;
      btn.addEventListener("click", () => {
        const willOpen = !node.classList.contains("is-open");
        nodes.forEach((n) => setOpen(n, false));
        setOpen(node, willOpen);
        if (willOpen && !reduceMotion) {
          node.scrollIntoView({ behavior: "smooth", block: "nearest" });
        }
      });
    });

    const updateFill = () => {
      if (!track || !fill) return;
      const visible = nodes.filter((n) => !n.hidden);
      if (!visible.length) {
        fill.style.height = "0%";
        return;
      }
      const rect = track.getBoundingClientRect();
      const vh = window.innerHeight || 1;
      const start = rect.top + window.scrollY;
      const end = start + rect.height;
      const center = window.scrollY + vh * 0.45;
      const pct = Math.max(0, Math.min(1, (center - start) / Math.max(1, end - start))) * 100;
      fill.style.height = pct + "%";
      visible.forEach((node) => {
        const r = node.getBoundingClientRect();
        const mid = r.top + r.height / 2;
        node.classList.toggle("is-inview", mid < vh * 0.72 && mid > vh * 0.08);
      });
    };

    const applyFilter = (key) => {
      filters.forEach((f) => {
        const on = f.dataset.filter === key;
        f.classList.toggle("is-active", on);
        f.setAttribute("aria-pressed", on ? "true" : "false");
      });
      nodes.forEach((node) => {
        const match = key === "all" || node.dataset.region === key;
        node.hidden = !match;
        if (!match) setOpen(node, false);
      });
      if (hint) {
        const map = {
          all: hint.dataset.hintAll || "",
          de: hint.dataset.hintDe || "",
          lb: hint.dataset.hintLb || "",
          sa: hint.dataset.hintSa || "",
        };
        hint.textContent = map[key] || map.all;
      }
      updateFill();
    };

    filters.forEach((f) => f.addEventListener("click", () => applyFilter(f.dataset.filter)));

    if ("IntersectionObserver" in window && !reduceMotion) {
      const io = new IntersectionObserver(
        (entries) => entries.forEach((e) => e.isIntersecting && e.target.classList.add("is-visible")),
        { threshold: 0.18, rootMargin: "0px 0px -8% 0px" }
      );
      nodes.forEach((n) => io.observe(n));
    } else {
      nodes.forEach((n) => n.classList.add("is-visible"));
    }

    window.addEventListener("scroll", updateFill, { passive: true });
    window.addEventListener("resize", updateFill);
    applyFilter("all");
    updateFill();
    const first = nodes.find((n) => !n.hidden);
    if (first) setOpen(first, true);
  }

  /* ========== Learning path ========== */
  const learning = document.querySelector("[data-learning]");
  if (learning) {
    const steps = [...learning.querySelectorAll("[data-learn-step]")];
    const panels = [...learning.querySelectorAll("[data-learn-panel]")];
    const progress = learning.querySelector(".learn-progress-bar");
    const counter = learning.querySelector("[data-learn-counter]");

    const activate = (id) => {
      steps.forEach((s) => {
        const on = s.dataset.learnStep === id;
        s.classList.toggle("is-active", on);
        s.setAttribute("aria-selected", on ? "true" : "false");
      });
      panels.forEach((p) => {
        const on = p.dataset.learnPanel === id;
        p.classList.toggle("is-active", on);
        p.hidden = !on;
      });
      const idx = Math.max(0, steps.findIndex((s) => s.dataset.learnStep === id));
      if (progress) progress.style.width = ((idx + 1) / steps.length) * 100 + "%";
      if (counter) counter.textContent = `${idx + 1} / ${steps.length}`;
    };

    steps.forEach((s) => {
      s.addEventListener("click", () => activate(s.dataset.learnStep));
      s.addEventListener("keydown", (e) => {
        if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
        e.preventDefault();
        const i = steps.indexOf(s);
        const next = e.key === "ArrowRight" ? steps[i + 1] : steps[i - 1];
        if (next) {
          next.focus();
          activate(next.dataset.learnStep);
        }
      });
    });

    const initial = steps.find((s) => s.classList.contains("is-active")) || steps[steps.length - 1];
    if (initial) activate(initial.dataset.learnStep);
  }

  /* ========== Skills constellation ========== */
  const skills = document.querySelector("[data-skills]");
  if (skills) {
    const chips = [...skills.querySelectorAll("[data-skill-filter]")];
    const nodes = [...skills.querySelectorAll(".skill-node")];
    const stage = skills.querySelector(".skill-stage");
    const readout = skills.querySelector("[data-skill-readout]");
    const titleEl = skills.querySelector("[data-skill-title]");
    const bodyEl = skills.querySelector("[data-skill-body]");
    const meterEl = skills.querySelector("[data-skill-meter]");

    const defaultTitle = titleEl ? titleEl.textContent : "";
    const defaultBody = bodyEl ? bodyEl.textContent : "";

    const applySkillFilter = (key) => {
      chips.forEach((c) => {
        const on = c.dataset.skillFilter === key;
        c.classList.toggle("is-active", on);
        c.setAttribute("aria-pressed", on ? "true" : "false");
      });
      nodes.forEach((n) => {
        const match = key === "all" || n.dataset.skillCat === key;
        n.classList.toggle("is-dim", !match);
        n.classList.toggle("is-lit", match && key !== "all");
        if (!match) n.classList.remove("is-selected");
      });
      if (key === "all" && titleEl && bodyEl) {
        titleEl.textContent = defaultTitle;
        bodyEl.textContent = defaultBody;
        if (meterEl) meterEl.style.width = "0%";
        readout && readout.classList.remove("has-selection");
      }
    };

    const selectSkill = (node) => {
      nodes.forEach((n) => n.classList.remove("is-selected"));
      node.classList.add("is-selected");
      if (titleEl) titleEl.textContent = node.dataset.skillName || node.textContent.trim();
      if (bodyEl) bodyEl.textContent = node.dataset.skillBlurb || "";
      if (meterEl) {
        meterEl.style.width = "0%";
        requestAnimationFrame(() => {
          meterEl.style.width = (node.dataset.skillLevel || "70") + "%";
        });
      }
      readout && readout.classList.add("has-selection");
    };

    chips.forEach((c) => c.addEventListener("click", () => applySkillFilter(c.dataset.skillFilter)));
    nodes.forEach((n) => {
      n.addEventListener("click", () => selectSkill(n));
      n.addEventListener("mouseenter", () => {
        if (!reduceMotion) n.classList.add("is-hover");
      });
      n.addEventListener("mouseleave", () => n.classList.remove("is-hover"));
    });

    if (stage && !reduceMotion) {
      stage.addEventListener("pointermove", (e) => {
        const r = stage.getBoundingClientRect();
        const x = ((e.clientX - r.left) / r.width - 0.5) * 12;
        const y = ((e.clientY - r.top) / r.height - 0.5) * 12;
        stage.style.setProperty("--mx", x.toFixed(2) + "px");
        stage.style.setProperty("--my", y.toFixed(2) + "px");
      });
      stage.addEventListener("pointerleave", () => {
        stage.style.setProperty("--mx", "0px");
        stage.style.setProperty("--my", "0px");
      });
    }

    applySkillFilter("all");
  }

  /* ========== Language reach ========== */
  const langs = document.querySelector("[data-langs]");
  if (langs) {
    const buttons = [...langs.querySelectorAll(".lang-live")];
    const totalEl = langs.querySelector("[data-lang-total]");
    const pctEl = langs.querySelector("[data-lang-world-pct]");
    const fillEl = langs.querySelector("[data-lang-world-fill]");
    const coreEl = langs.querySelector("[data-lang-core]");
    const humansLabel = langs.querySelector("[data-lang-humans-label]");
    const worldLabel = langs.querySelector("[data-lang-world-label]");
    const worldPop = Number(langs.dataset.worldPop || 8100000000);
    let animToken = 0;

    if (humansLabel && langs.dataset.labelHumans) {
      humansLabel.textContent = langs.dataset.labelHumans;
    }
    if (worldLabel && langs.dataset.labelWorld) {
      worldLabel.textContent = langs.dataset.labelWorld;
    }

    const formatCompact = (n) => {
      if (n >= 1e9) return (n / 1e9).toFixed(2).replace(/\.?0+$/, "") + "B";
      if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e8 ? 0 : 1).replace(/\.0$/, "") + "M";
      return Math.round(n).toLocaleString();
    };

    const formatFull = (n) => Math.round(n).toLocaleString();
    const isDe = document.documentElement.lang === "de";

    const animateNumber = (el, from, to, ms = 650) => {
      const token = ++animToken;
      if (reduceMotion) {
        el.textContent = formatFull(to);
        return;
      }
      const start = performance.now();
      const tick = (now) => {
        if (token !== animToken) return;
        const t = Math.min(1, (now - start) / ms);
        const eased = 1 - Math.pow(1 - t, 3);
        el.textContent = formatFull(from + (to - from) * eased);
        if (t < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    };

    const update = (animate = true) => {
      const active = buttons.filter((b) => b.classList.contains("is-on"));
      const sum = active.reduce((acc, b) => acc + Number(b.dataset.speakers || 0), 0);
      const prev = Number((totalEl && totalEl.dataset.value) || 0);
      if (totalEl) {
        totalEl.dataset.value = String(sum);
        if (animate) animateNumber(totalEl, prev, sum);
        else totalEl.textContent = formatFull(sum);
      }
      const pct = worldPop > 0 ? (sum / worldPop) * 100 : 0;
      if (pctEl) pctEl.textContent = pct.toFixed(1);
      if (fillEl) fillEl.style.width = Math.min(100, pct) + "%";
      if (coreEl) {
        coreEl.textContent = active.length
          ? active.map((b) => b.dataset.lang.toUpperCase()).join(" · ")
          : "—";
      }
      langs.classList.toggle("is-hot", active.length > 0);
      const unit = isDe ? " Sprecher" : " speakers";
      buttons.forEach((b) => {
        const count = b.querySelector("[data-lang-count]");
        if (!count) return;
        const n = Number(b.dataset.speakers || 0);
        count.textContent = formatCompact(n) + unit;
      });
    };

    buttons.forEach((b) => {
      const count = b.querySelector("[data-lang-count]");
      if (count) {
        const n = Number(b.dataset.speakers || 0);
        count.textContent = formatCompact(n) + (isDe ? " Sprecher" : " speakers");
      }
      b.addEventListener("click", () => {
        const on = b.classList.contains("is-on");
        const othersOn = buttons.filter((x) => x !== b && x.classList.contains("is-on")).length;
        if (on && othersOn === 0) {
          langs.classList.add("is-shake");
          setTimeout(() => langs.classList.remove("is-shake"), 400);
          return;
        }
        b.classList.toggle("is-on");
        b.setAttribute("aria-pressed", b.classList.contains("is-on") ? "true" : "false");
        update(true);
      });

      b.addEventListener("pointerenter", () => {
        if (!reduceMotion) langs.classList.add("is-hot");
      });
    });

    // Pointer parallax on pulse
    const pulse = langs.querySelector(".lang-pulse");
    if (pulse && !reduceMotion) {
      pulse.addEventListener("pointermove", (e) => {
        const r = pulse.getBoundingClientRect();
        const x = ((e.clientX - r.left) / r.width - 0.5) * 10;
        const y = ((e.clientY - r.top) / r.height - 0.5) * 10;
        if (coreEl) coreEl.style.transform = `translate(${x}px, ${y}px)`;
      });
      pulse.addEventListener("pointerleave", () => {
        if (coreEl) coreEl.style.transform = "";
      });
    }

    // Animate when section enters view
    const boot = () => update(true);
    if ("IntersectionObserver" in window) {
      let done = false;
      const io = new IntersectionObserver(
        (entries) => {
          if (done) return;
          if (entries.some((e) => e.isIntersecting)) {
            done = true;
            boot();
            io.disconnect();
          }
        },
        { threshold: 0.25 }
      );
      io.observe(langs);
    } else {
      boot();
    }
  }
})();
