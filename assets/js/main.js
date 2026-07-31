(() => {
  const rows = document.querySelectorAll(".post-row");
  if (!rows.length || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.style.animationPlayState = "running";
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12 }
  );

  rows.forEach((row) => {
    row.style.animationPlayState = "paused";
    io.observe(row);
  });
})();
