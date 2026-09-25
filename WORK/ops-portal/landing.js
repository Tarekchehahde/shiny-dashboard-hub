(function () {
  var toggle = document.querySelector(".nav-toggle");
  var menu = document.getElementById("nav-menu");
  var nav = document.querySelector(".site-nav");
  if (!toggle || !menu || !nav) return;

  function setOpen(open) {
    toggle.setAttribute("aria-expanded", open ? "true" : "false");
    menu.classList.toggle("is-open", open);
    document.body.classList.toggle("nav-open", open);
  }

  toggle.addEventListener("click", function () {
    setOpen(toggle.getAttribute("aria-expanded") !== "true");
  });

  menu.querySelectorAll("a").forEach(function (link) {
    link.addEventListener("click", function () { setOpen(false); });
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") setOpen(false);
  });

  function onScroll() {
    nav.classList.toggle("is-scrolled", window.scrollY > 8);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();
})();
