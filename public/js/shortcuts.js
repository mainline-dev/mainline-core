(function() {
  var selected = null;
  var gPrefix = false;
  var gTimer = null;

  document.addEventListener('keydown', function(e) {
    if (e.target.matches('input, textarea, select, [contenteditable]')) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;

    var modal = document.getElementById('shortcuts-modal');

    if (gPrefix) {
      gPrefix = false;
      clearTimeout(gTimer);
      var base = document.body.dataset.teamBase;
      if (!base) return;
      var routes = { m: '', f: '/flow', t: '/teamwork', i: '/inventory' };
      if (routes.hasOwnProperty(e.key)) {
        e.preventDefault();
        location.href = base + routes[e.key];
        return;
      }
      var link = document.querySelector('a[data-shortcut-key="' + CSS.escape(e.key) + '"]');
      if (link) {
        e.preventDefault();
        location.href = link.getAttribute('href');
      }
      return;
    }

    var cards = visualSortedCards();

    switch (e.key) {
      case '?':
        e.preventDefault();
        if (modal) modal.classList.toggle('shortcuts-open');
        break;
      case 'Escape':
        if (modal && modal.classList.contains('shortcuts-open')) {
          modal.classList.remove('shortcuts-open');
        }
        if (selected) {
          selected.classList.remove('story-card--focus');
          selected = null;
        }
        break;
      case 'g':
        gPrefix = true;
        gTimer = setTimeout(function() { gPrefix = false; }, 1000);
        break;
      case 'j':
        if (!cards.length) break;
        e.preventDefault();
        selected = nextCard(cards, selected, 1);
        renderFocus(cards, selected);
        break;
      case 'k':
        if (!cards.length) break;
        e.preventDefault();
        selected = nextCard(cards, selected, -1);
        renderFocus(cards, selected);
        break;
      case 'Enter':
        if (selected) {
          e.preventDefault();
          var panel = selected.querySelector('.story-title-link');
          if (panel) panel.click();
        }
        break;
      case 'e':
        if (selected) {
          var edit = selected.querySelector('a[href*="/edit"]');
          if (edit) location.href = edit.href;
        }
        break;
    }
  });

  function visualSortedCards() {
    return Array.from(document.querySelectorAll('.story-card')).sort(function(a, b) {
      var ra = a.getBoundingClientRect();
      var rb = b.getBoundingClientRect();
      var rowDelta = Math.round(ra.top / 20) - Math.round(rb.top / 20);
      if (rowDelta !== 0) return rowDelta;
      return ra.left - rb.left;
    });
  }

  function nextCard(cards, current, delta) {
    var i = cards.indexOf(current);
    var next = i + delta;
    if (next < 0) next = 0;
    if (next >= cards.length) next = cards.length - 1;
    return cards[next] || cards[0];
  }

  function renderFocus(cards, card) {
    cards.forEach(function(c) { c.classList.remove('story-card--focus'); });
    if (!card) return;
    card.classList.add('story-card--focus');

    var container = card.closest('.map-grid-container');
    if (container) {
      var cardRect = card.getBoundingClientRect();
      var containerRect = container.getBoundingClientRect();
      var pad = 24;
      if (cardRect.right > containerRect.right - pad) {
        container.scrollLeft += (cardRect.right - containerRect.right) + pad;
      } else if (cardRect.left < containerRect.left + pad) {
        container.scrollLeft -= (containerRect.left - cardRect.left) + pad;
      }
      if (cardRect.top < 0 || cardRect.bottom > window.innerHeight) {
        window.scrollBy({ top: cardRect.top - 120, behavior: 'auto' });
      }
    }
  }
})();
