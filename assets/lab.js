/* ========== COLLAPSIBLE SECTIONS ========== */
let introDeckSlide = 0;
const introTotalSlides = 4;

function collapseSetup() {
  const section = document.getElementById('setup-section');
  const toggle = document.getElementById('setup-toggle');
  if (section) section.classList.remove('expanded');
  if (toggle) toggle.classList.remove('open');
}

function collapseIntroDeck() {
  const deck = document.getElementById('intro-deck');
  const toggle = document.getElementById('intro-deck-toggle');
  if (deck) deck.classList.remove('expanded');
  if (toggle) toggle.classList.remove('open');
}

function toggleSetup() {
  const section = document.getElementById('setup-section');
  const toggle = document.getElementById('setup-toggle');
  section.classList.toggle('expanded');
  toggle.classList.toggle('open');
}

function toggleIntroDeck() {
  const deck = document.getElementById('intro-deck');
  const toggle = document.getElementById('intro-deck-toggle');
  const isOpening = !deck.classList.contains('expanded');
  deck.classList.toggle('expanded');
  toggle.classList.toggle('open');
  if (isOpening) collapseSetup();
}

function startLab() {
  collapseIntroDeck();
  collapseSetup();
}

function introDeckGo(n) {
  introDeckSlide = n;
  document.querySelectorAll('#intro-deck .deck-slide').forEach((s, i) => s.classList.toggle('active', i === n));
  document.querySelectorAll('#intro-deck .deck-dot').forEach((d, i) => d.classList.toggle('active', i === n));
  const numEl = document.getElementById('intro-slide-num');
  if (numEl) numEl.textContent = n + 1;
}

function introDeckNav(dir) {
  const next = introDeckSlide + dir;
  if (next >= 0 && next < introTotalSlides) introDeckGo(next);
}

document.addEventListener('DOMContentLoaded', () => {
  const steps = document.querySelectorAll('.step');
  const navItems = document.querySelectorAll('.nav-item');
  const flowCards = document.querySelectorAll('.flow-card');
  const themeBtn = document.querySelector('.theme-toggle');
  let currentStep = 0;

  function showStep(idx) {
    if (idx < 0 || idx >= steps.length) return;
    steps.forEach(s => s.classList.remove('active'));
    navItems.forEach(n => n.classList.remove('active'));
    flowCards.forEach(c => c.classList.remove('active'));
    steps[idx].classList.add('active');
    if (navItems[idx]) navItems[idx].classList.add('active');
    if (flowCards[idx]) flowCards[idx].classList.add('active');
    currentStep = idx;
    window.scrollTo({ top: document.querySelector('.docs-content').offsetTop - 20, behavior: 'smooth' });
  }

  navItems.forEach((item, i) => item.addEventListener('click', () => showStep(i)));
  flowCards.forEach((card, i) => card.addEventListener('click', () => showStep(i)));

  document.querySelectorAll('.nav-btn-prev').forEach(btn =>
    btn.addEventListener('click', () => showStep(currentStep - 1)));
  document.querySelectorAll('.nav-btn-next').forEach(btn =>
    btn.addEventListener('click', () => showStep(currentStep + 1)));

  // Copy buttons
  document.querySelectorAll('.copy-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.closest('.code-block').querySelector('pre').textContent;
      navigator.clipboard.writeText(code).then(() => {
        const orig = btn.textContent;
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = orig; btn.classList.remove('copied'); }, 2000);
      });
    });
  });

  // Theme toggle
  if (themeBtn) {
    const saved = localStorage.getItem('buh-lab-theme');
    if (saved === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
    themeBtn.addEventListener('click', () => {
      const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
      if (isDark) {
        document.documentElement.removeAttribute('data-theme');
        localStorage.setItem('buh-lab-theme', 'light');
      } else {
        document.documentElement.setAttribute('data-theme', 'dark');
        localStorage.setItem('buh-lab-theme', 'dark');
      }
    });
  }

  // Keyboard nav (deck takes priority when expanded)
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    const deck = document.getElementById('intro-deck');
    if (deck && deck.classList.contains('expanded')) {
      if (e.key === 'ArrowRight') { introDeckNav(1); e.preventDefault(); }
      if (e.key === 'ArrowLeft') { introDeckNav(-1); e.preventDefault(); }
      return;
    }
    if (e.key === 'ArrowRight') { e.preventDefault(); showStep(currentStep + 1); }
    if (e.key === 'ArrowLeft') { e.preventDefault(); showStep(currentStep - 1); }
  });

  showStep(0);
});
