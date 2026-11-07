document.addEventListener('submit', function(e) {
  var btn = e.target.querySelector('button[type="submit"]');
  if (btn && !e.target.hasAttribute('hx-post')) btn.disabled = true;
});

// A form being sent has its button held until the answer comes; a search box
// or a plain button inside a form is not the form being sent.
document.addEventListener('htmx:beforeRequest', function(e) {
  if (e.detail.elt.matches('input, select, textarea, button[type="button"]')) return;
  var form = e.detail.elt.closest('form') || e.detail.elt;
  var btn = form.querySelector('button[type="submit"]');
  if (btn) { btn.disabled = true; btn.dataset.htmxDisabled = '1'; }
});

document.addEventListener('htmx:afterRequest', function(e) {
  var form = e.detail.elt.closest('form') || e.detail.elt;
  var btn = form.querySelector('button[type="submit"][data-htmx-disabled]');
  if (btn) { btn.disabled = false; delete btn.dataset.htmxDisabled; }
});

document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.flash').forEach(function(el) {
    setTimeout(function() {
      el.style.transition = 'opacity 0.3s ease';
      el.style.opacity = '0';
      setTimeout(function() { el.remove(); }, 300);
    }, 4000);
  });

  if (typeof tippy !== 'undefined') {
    tippy('[data-tippy-content]', {
      delay: [50, 100],
      duration: [100, 100],
      placement: 'top'
    });
    document.addEventListener('htmx:afterSwap', function() {
      tippy('[data-tippy-content]', {
        delay: [0, 0],
        duration: [100, 100],
        placement: 'top'
      });
    });
  }
});

document.addEventListener('input', function(e) {
  var form = e.target.closest('.scenario-form, .story-edit-form, .dirty-form');
  if (!form) return;
  var btn = form.querySelector('button[type="submit"]');
  if (btn) btn.disabled = false;
});

(function() {
  function getCounter(input) {
    var counter = input.nextElementSibling;
    if (counter && counter.classList.contains('char-counter')) return counter;

    var wrapper = input.parentElement;
    if (!wrapper || !wrapper.classList.contains('char-counter-wrap')) {
      wrapper = document.createElement('div');
      wrapper.className = 'char-counter-wrap';
      input.parentNode.insertBefore(wrapper, input);
      wrapper.appendChild(input);
    }

    counter = document.createElement('span');
    counter.className = 'char-counter';
    input.insertAdjacentElement('afterend', counter);
    return counter;
  }

  function updateCounter(input) {
    var max = input.getAttribute('maxlength');
    if (!max) return;
    max = parseInt(max, 10);

    var counter = getCounter(input);
    var remaining = max - input.value.length;
    counter.textContent = remaining;
    counter.classList.toggle('char-counter-warn', remaining <= Math.ceil(max * 0.1));
    counter.classList.toggle('char-counter-full', remaining <= 0);
    counter.style.display = input === document.activeElement ? '' : 'none';
  }

  var SEL = 'input[maxlength]:not([data-title]), textarea[maxlength]';

  document.addEventListener('input', function(e) {
    if (e.target.matches(SEL)) updateCounter(e.target);
  });

  document.addEventListener('focusin', function(e) {
    if (e.target.matches(SEL)) updateCounter(e.target);
  });

  document.addEventListener('focusout', function(e) {
    if (!e.target.matches(SEL)) return;
    var counter = e.target.nextElementSibling;
    if (counter && counter.classList.contains('char-counter')) counter.style.display = 'none';
  });

  function wrapAll() {
    document.querySelectorAll(SEL).forEach(function(input) { getCounter(input); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', wrapAll);
  } else {
    wrapAll();
  }

  document.addEventListener('htmx:afterSwap', wrapAll);
})();

document.addEventListener('change', function(e) {
  var form = e.target.closest('.story-edit-form, .dirty-form');
  if (!form) return;
  var btn = form.querySelector('button[type="submit"]');
  if (btn) btn.disabled = false;

  if (e.target.id === 'decoupling_strategy') {
    var group = document.getElementById('decoupling-label-group');
    if (group) group.style.display = e.target.value ? '' : 'none';
  }
});

document.addEventListener('htmx:afterSwap', function() {
  var container = document.getElementById('story-form-container');
  if (!container || !container.hasAttribute('data-save-success')) return;

  var btn = container.querySelector('button[type="submit"]');
  if (!btn) return;
  btn.textContent = 'Saved';
  btn.classList.add('btn-saved');
  btn.disabled = true;

  setTimeout(function() {
    btn.textContent = 'Save';
    btn.classList.remove('btn-saved');
  }, 1500);
});

document.addEventListener('click', function(e) {
  var btn = e.target.closest('.delete-confirm');
  if (!btn) return;
  e.preventDefault();

  if (btn.dataset.confirming) {
    btn.disabled = true;
    htmx.ajax('POST', btn.dataset.deleteUrl, {
      target: btn.dataset.deleteTarget,
      swap: 'outerHTML'
    });
    return;
  }

  var label = btn.dataset.label || '×';
  btn.dataset.confirming = 'true';
  btn.textContent = 'confirm?';
  btn.classList.add('delete-confirming');
  btn.setAttribute('aria-live', 'assertive');

  setTimeout(function() {
    delete btn.dataset.confirming;
    btn.textContent = label;
    btn.classList.remove('delete-confirming');
    btn.removeAttribute('aria-live');
  }, 3000);
});

document.addEventListener('showFlash', function(e) {
  var detail = e.detail;
  var el = document.createElement('div');
  el.className = 'flash' + (detail.type === 'error' ? ' flash-error' : '');
  el.textContent = detail.message;
  el.setAttribute('data-test-id', 'flash-' + detail.type);
  if (detail.reason) el.dataset.reason = detail.reason;
  var main = document.getElementById('main');
  if (main) {
    main.insertBefore(el, main.firstChild);
  } else {
    document.body.insertBefore(el, document.body.firstChild);
  }
  setTimeout(function() {
    el.style.transition = 'opacity 0.3s ease';
    el.style.opacity = '0';
    setTimeout(function() { el.remove(); }, 300);
  }, 4000);
});

document.addEventListener('htmx:beforeRequest', function(e) {
  var grid = e.detail.target && e.detail.target.closest('.map-grid-container');
  if (grid) grid.classList.add('htmx-loading');
});

document.addEventListener('htmx:afterSwap', function(e) {
  var grid = e.detail.target && e.detail.target.closest('.map-grid-container');
  if (grid) grid.classList.remove('htmx-loading');
  document.querySelectorAll('.map-grid-container.htmx-loading').forEach(function(el) {
    el.classList.remove('htmx-loading');
  });
});

document.addEventListener('htmx:responseError', function(e) {
  var grid = e.detail.target && e.detail.target.closest('.map-grid-container');
  if (grid) grid.classList.remove('htmx-loading');
  var xhr = e.detail.xhr;
  var ct = xhr.getResponseHeader('Content-Type') || '';
  var msg;
  if (ct.indexOf('application/json') !== -1) {
    try { msg = JSON.parse(xhr.responseText).error; } catch (_) { msg = null; }
  } else if (ct.indexOf('text/html') !== -1 || xhr.responseText.indexOf('<!DOCTYPE') !== -1) {
    msg = null;
  } else {
    msg = xhr.responseText;
  }
  if (!msg || msg.length > 200) msg = 'Something went wrong. Reload and try again.';
  var flash = document.createElement('div');
  flash.className = 'flash flash-error';
  flash.textContent = msg;
  document.body.insertBefore(flash, document.body.firstChild);
  setTimeout(function() { flash.remove(); }, 4000);
});

document.addEventListener('click', function(e) {
  var link = e.target.closest('.story-title-link[hx-get]');
  if (link) e.preventDefault();
});

document.addEventListener('click', function(e) {
  if (e.target.closest('.inline-assign-dropdown')) return;

  document.querySelectorAll('.inline-assign-dropdown').forEach(function(dd) {
    dd.remove();
  });
});

var closePanelTimer = null;
function closeStoryPanel() {
  var container = document.getElementById('story-panel-container');
  if (!container) return;
  var panel = container.querySelector('.slide-panel');
  if (panel) {
    panel.style.animation = 'none';
    panel.style.transform = 'translateX(100%)';
    panel.style.transition = 'transform 250ms ease';
  }
  var expand = container.querySelector('.story-expand');
  if (expand) {
    expand.style.transition = 'transform 250ms ease, opacity 250ms ease';
    expand.style.transform = 'translateX(-100%)';
    expand.style.opacity = '0';
  }
  var backdrop = container.querySelector('.story-expand-backdrop');
  if (backdrop) {
    backdrop.style.transition = 'opacity 200ms ease';
    backdrop.style.opacity = '0';
  }
  if (closePanelTimer) clearTimeout(closePanelTimer);
  closePanelTimer = setTimeout(function() {
    closePanelTimer = null;
    container.innerHTML = '';
  }, 250);
}

document.addEventListener('keydown', function(e) {
  var container = document.getElementById('story-panel-container');
  var panel = container && container.querySelector('.slide-panel');
  if (!panel) return;

  if (e.key === 'Escape') {
    e.preventDefault();
    e.stopPropagation();
    closeStoryPanel();
    return;
  }

  if (e.key === 'Tab') {
    var focusable = panel.querySelectorAll('input:not([disabled]), select:not([disabled]), textarea:not([disabled]), button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])');
    if (!focusable.length) return;
    var first = focusable[0];
    var last = focusable[focusable.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }
}, true);

document.addEventListener('click', function(e) {
  if (e.target.closest('[data-test-id="panel-close"]') ||
      e.target.matches('[data-test-id="panel-backdrop"]')) {
    closeStoryPanel();
  }
});

document.addEventListener('htmx:afterSwap', function(e) {
  var panelContainer = document.getElementById('story-panel-container');
  if (panelContainer && e.detail.target === panelContainer && panelContainer.querySelector('.slide-panel')) {
    if (closePanelTimer) { clearTimeout(closePanelTimer); closePanelTimer = null; }
    htmx.process(panelContainer);
    var form = panelContainer.querySelector('.story-edit-form');
    if (form) {
      var firstInput = form.querySelector('input[type="text"]');
      if (firstInput) firstInput.focus();
    }
  }
});

document.addEventListener('htmx:afterSwap', function() {
  var container = document.getElementById('story-panel-container');
  if (!container) return;
  var formContainer = container.querySelector('[data-save-success]');
  if (!formContainer) return;

  formContainer.removeAttribute('data-save-success');

  var form = formContainer.querySelector('form');
  if (!form) return;
  var action = form.getAttribute('action') || '';
  var match = action.match(/\/maps\/([^/]+)\/stories\/([^/]+)$/);
  if (!match) return;
  var mapId = match[1];
  var storyId = match[2];
  var card = document.querySelector('.story-card[data-id="' + storyId + '"]');
  if (!card) return;

  var taskSelect = formContainer.querySelector('#task_id');
  var sliceSelect = formContainer.querySelector('#release_slice_id');
  var container = card.closest('.task-stories');
  var taskChanged = taskSelect && container && container.dataset.taskId !== taskSelect.value;
  var sliceChanged = sliceSelect && container && container.dataset.sliceId !== (sliceSelect.value || undefined);

  if (taskChanged || sliceChanged) {
    var gridEl = document.querySelector('.map-grid-container');
    if (gridEl) gridEl.classList.add('htmx-loading');
    htmx.ajax('GET', '/maps/' + mapId + '/grid', {
      target: '.map-grid-container',
      swap: 'outerHTML'
    });
  } else {
    htmx.ajax('GET', '/maps/' + mapId + '/stories/' + storyId + '/card', {
      target: card,
      swap: 'outerHTML'
    });
  }
});

(function() {
  var map = document.querySelector('.map-grid');
  if (!map) return;
  var teamId = map.dataset.teamId || 'default';
  var key = 'mainline-density-' + teamId;

  function apply(density) {
    document.body.dataset.density = density;
    document.querySelectorAll('button[data-density]').forEach(function(btn) {
      btn.classList.toggle('density-active', btn.dataset.density === density);
    });
  }

  apply(localStorage.getItem(key) || 'comfortable');

  document.querySelectorAll('button[data-density]').forEach(function(btn) {
    btn.addEventListener('click', function(e) {
      e.preventDefault();
      var density = btn.dataset.density;
      localStorage.setItem(key, density);
      apply(density);
    });
  });
})();

document.addEventListener('click', function(e) {
  var btn = e.target.closest('.preview-copy-id');
  if (!btn) return;
  var id = btn.dataset.storyId;
  if (!id) return;
  var original = btn.textContent;
  btn.style.minWidth = btn.offsetWidth + 'px';
  navigator.clipboard.writeText(id).then(function() {
    btn.classList.add('copied');
    btn.textContent = 'Copied';
    setTimeout(function() {
      btn.classList.remove('copied');
      btn.textContent = original;
      btn.style.minWidth = '';
    }, 1500);
  });
});

(function() {
  var KEBAB = 'details.card-kebab, details.subnav-kebab';

  document.addEventListener('toggle', function(e) {
    if (!e.target.matches(KEBAB)) return;
    if (!e.target.open) return;
    document.querySelectorAll(KEBAB).forEach(function(d) {
      if (d !== e.target && d.open) d.open = false;
    });
  }, true);

  document.addEventListener('click', function(e) {
    document.querySelectorAll(KEBAB).forEach(function(d) {
      if (d.open && !d.contains(e.target)) d.open = false;
    });
  });

  document.addEventListener('keydown', function(e) {
    if (e.key !== 'Escape') return;
    document.querySelectorAll(KEBAB).forEach(function(d) {
      if (d.open) d.open = false;
    });
  });
})();

function monitorPost(form) {
  var body = document.body;
  var headers = { 'Content-Type': 'application/x-www-form-urlencoded', 'HX-Request': 'true' };
  try { Object.assign(headers, JSON.parse(body.getAttribute('hx-headers'))); } catch (_) {}
  fetch(form.action, {
    method: 'POST',
    headers: headers,
    body: new URLSearchParams(new FormData(form)),
    credentials: 'same-origin',
    redirect: 'manual'
  }).then(function(r) {
    if (r.type === 'opaqueredirect' || !r.ok) { window.location.reload(); return ''; }
    return r.text();
  }).then(function(html) {
    if (!html) return;
    var main = document.getElementById('main');
    main.innerHTML = html;
    htmx.process(main);
  });
}

document.addEventListener('change', function(e) {
  var select = e.target.closest('.monitor-threshold-select');
  if (!select) return;
  var form = select.closest('form');
  if (form) monitorPost(form);
});

document.addEventListener('click', function(e) {
  var btn = e.target.closest('.monitor-spike-btn, .monitor-unspike-btn');
  if (!btn) return;
  e.preventDefault();
  var form = btn.closest('form');
  if (form) monitorPost(form);
});

document.addEventListener('click', function(e) {
  var toggle = e.target.closest('.monitor-help-toggle');
  var p = document.getElementById('monitor-help-popover');
  if (!p) return;

  if (toggle) {
    var open = !p.hasAttribute('hidden');
    if (open) { p.setAttribute('hidden', ''); toggle.setAttribute('aria-expanded', 'false'); }
    else { p.removeAttribute('hidden'); toggle.setAttribute('aria-expanded', 'true'); }
    return;
  }

  if (!p.hasAttribute('hidden') && !p.contains(e.target)) {
    p.setAttribute('hidden', '');
    var btn = document.querySelector('.monitor-help-toggle');
    if (btn) btn.setAttribute('aria-expanded', 'false');
  }
});

document.addEventListener('click', function(e) {
  var orgToggle = e.target.closest('.monitor-org-toggle');
  if (orgToggle) {
    var group = orgToggle.closest('.monitor-org-group');
    var expanded = orgToggle.getAttribute('aria-expanded') === 'true';
    orgToggle.setAttribute('aria-expanded', expanded ? 'false' : 'true');
    group.setAttribute('data-expanded', expanded ? 'false' : 'true');
    return;
  }

  var toggle = e.target.closest('.monitor-repo-toggle');
  if (toggle) {
    var repo = toggle.closest('.monitor-repo');
    if (repo.dataset.status !== 'green') return;
    var expanded = repo.getAttribute('data-expanded') === 'true';
    repo.setAttribute('data-expanded', expanded ? 'false' : 'true');
    toggle.setAttribute('aria-expanded', expanded ? 'false' : 'true');
    return;
  }

  var showAll = e.target.closest('.monitor-show-all');
  if (showAll) {
    var list = document.querySelector('.monitor-repos');
    var pressed = showAll.getAttribute('aria-pressed') === 'true';
    list.setAttribute('data-show-all', pressed ? 'false' : 'true');
    showAll.setAttribute('aria-pressed', pressed ? 'true' : 'false');
    showAll.textContent = pressed
      ? 'Show all repos (' + list.querySelectorAll('.monitor-repo[data-status="green"]').length + ' healthy collapsed)'
      : 'Collapse healthy repos';
  }
});

// Ticket Museum upload: a CSV dropped anywhere on the page, or chosen, goes
// straight to the preview. Only the first dropped file is taken.
(function() {
  function dropForm() {
    return document.querySelector('form[data-drop-upload]');
  }

  function draggingAFile(e) {
    return e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types, 'Files') !== -1;
  }

  document.addEventListener('dragover', function(e) {
    if (!dropForm() || !draggingAFile(e)) return;
    e.preventDefault();
    document.body.classList.add('mu-dragging');
  });

  document.addEventListener('dragleave', function(e) {
    if (!e.relatedTarget) document.body.classList.remove('mu-dragging');
  });

  document.addEventListener('drop', function(e) {
    var form = dropForm();
    if (!form || !e.dataTransfer || !e.dataTransfer.files.length) return;
    e.preventDefault();
    document.body.classList.remove('mu-dragging');
    var first = new DataTransfer();
    first.items.add(e.dataTransfer.files[0]);
    form.querySelector('input[type="file"]').files = first.files;
    form.requestSubmit();
  });

  document.addEventListener('change', function(e) {
    var form = e.target.closest('form[data-drop-upload]');
    if (form && e.target.type === 'file' && e.target.files.length) form.requestSubmit();
  });
})();

// Ticket Museum selection: exhibits ticked in the list are kept for this tab
// across pages and filters, shown in the selection bar, and sent to storage
// together. Ticking a parent ticks its sub-tasks, which go with it.
document.addEventListener('DOMContentLoaded', function() {
  var bar = document.getElementById('mu-selection');
  if (!bar) return;
  var storeKey = 'museum-selection:' + bar.getAttribute('data-team');

  function load() {
    try { return JSON.parse(sessionStorage.getItem(storeKey)) || {}; } catch (e) { return {}; }
  }

  function save() {
    try { sessionStorage.setItem(storeKey, JSON.stringify(selected)); } catch (e) { /* kept for this page only */ }
  }

  var selected = load();

  function boxes() {
    return document.querySelectorAll('.mu-check[form="mu-selection"]');
  }

  function sync() {
    boxes().forEach(function(box) {
      box.checked = !!selected[box.value];
      var row = box.closest('.mu-row');
      if (row) row.classList.toggle('is-selected', box.checked);
      document.querySelectorAll('.mu-check-mirror[data-parent="' + box.getAttribute('data-key') + '"]').forEach(function(mirror) {
        mirror.checked = box.checked;
      });
    });
    var ids = Object.keys(selected);
    var keys = ids.map(function(id) { return selected[id].key; });
    var subtasks = ids.reduce(function(total, id) { return total + selected[id].subtasks; }, 0);
    var count = ids.length + subtasks;
    var shown = keys.slice(0, 6).join(' · ') + (keys.length > 6 ? ' …' : '');
    if (subtasks) shown += ' + ' + subtasks + (subtasks === 1 ? ' sub-task' : ' sub-tasks');
    bar.hidden = ids.length === 0;
    bar.setAttribute('data-count', count);
    bar.querySelector('[data-selection-count]').textContent = count + ' selected';
    bar.querySelector('[data-selection-keys]').textContent = shown;
  }

  document.addEventListener('change', function(e) {
    var box = e.target;
    if (!box.matches || !box.matches('.mu-check[form="mu-selection"]')) return;
    if (box.checked) {
      selected[box.value] = { key: box.getAttribute('data-key'), subtasks: Number(box.getAttribute('data-subtasks')) || 0 };
    } else {
      delete selected[box.value];
    }
    save();
    sync();
  });

  bar.querySelector('[data-selection-clear]').addEventListener('click', function() {
    selected = {};
    save();
    sync();
  });

  bar.addEventListener('submit', function() {
    var onPage = {};
    boxes().forEach(function(box) { onPage[box.value] = true; });
    Object.keys(selected).forEach(function(id) {
      if (onPage[id]) return;
      var input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'ids[]';
      input.value = id;
      bar.appendChild(input);
    });
    bar.querySelector('input[name="return_to"]').value = window.location.pathname + window.location.search;
    selected = {};
    save();
  });

  var together = document.getElementById('mu-together');
  together.addEventListener('submit', function() {
    together.querySelectorAll('input[name="ids[]"]').forEach(function(input) { input.remove(); });
    Object.keys(selected).forEach(function(id) {
      var input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'ids[]';
      input.value = id;
      together.appendChild(input);
    });
    together.querySelector('input[name="return_to"]').value = window.location.pathname + window.location.search;
  });

  document.body.addEventListener('htmx:afterSwap', sync);
  sync();
});

// Ticket Museum toasts stay for 8 seconds, counted from when the pointer or
// focus leaves. The browser tests shorten the wait through window.museumToastDelay.
function museumToastTimers() {
  document.querySelectorAll('[data-toast]').forEach(function(toast) {
    if (toast.timed) return;
    toast.timed = true;
    var timer;
    function leaveSoon() {
      timer = setTimeout(function() {
        toast.style.transition = 'opacity 0.3s ease';
        toast.style.opacity = '0';
        setTimeout(function() { toast.remove(); }, 300);
      }, window.museumToastDelay || 8000);
    }
    toast.addEventListener('mouseenter', function() { clearTimeout(timer); });
    toast.addEventListener('mouseleave', leaveSoon);
    toast.addEventListener('focusin', function() { clearTimeout(timer); });
    toast.addEventListener('focusout', leaveSoon);
    leaveSoon();
  });
}

document.addEventListener('DOMContentLoaded', museumToastTimers);
document.addEventListener('htmx:afterSwap', museumToastTimers);

// Ticket Museum let go: the counts, the group tick boxes and the button follow
// what is chosen on the page. A pair counts as one, kept rows don't count, and
// the rest of a group counts with its box.
function museumSetCount(el, count) {
  el.setAttribute('data-count', count);
  el.textContent = count;
}

function museumLetGoGroup(section) {
  var rest = section.querySelector('[data-rest]');
  var held = rest ? Number(rest.getAttribute('data-rest')) : 0;
  var chosen = section.querySelectorAll('.mu-lg-row .mu-check:checked, .mu-lg-side input:checked').length +
    (rest && rest.checked ? held : 0);
  var total = section.querySelectorAll('.mu-lg-row .mu-check, .mu-lg-pair').length + held;
  var tick = section.querySelector('[data-group-tick]');
  tick.checked = total > 0 && chosen === total;
  tick.indeterminate = chosen > 0 && chosen < total;
  var selected = section.querySelector('.mu-lg-title .mu-count');
  selected.setAttribute('data-count', chosen);
  selected.textContent = chosen + ' of ' + total + ' selected';
  return chosen;
}

function museumLetGoSync(form) {
  var going = 0;
  form.querySelectorAll('.mu-lg-group').forEach(function(section) { going += museumLetGoGroup(section); });
  var display = Number(form.getAttribute('data-on-display'));
  museumSetCount(form.querySelector('.mu-lg-tally-go strong'), going);
  museumSetCount(form.querySelector('.mu-lg-tally-stay strong'), display - going);
  form.querySelector('[data-impact]').style.width = (display ? going / display * 100 : 0) + '%';
  var submit = form.querySelector('button[type="submit"]');
  submit.setAttribute('data-count', going);
  submit.textContent = 'Let go of ' + going + (going === 1 ? ' exhibit' : ' exhibits');
  submit.disabled = going === 0 && !form.querySelector('.mu-lg-both input:checked');
}

function museumLetGoSyncAll() {
  var form = document.querySelector('[data-let-go]');
  if (form) museumLetGoSync(form);
}

function museumTickGroup(section, on) {
  section.querySelectorAll('.mu-lg-row .mu-check, [data-rest]').forEach(function(box) { box.checked = on; });
  section.querySelectorAll('.mu-lg-pair').forEach(function(pair) {
    var sides = pair.querySelectorAll('.mu-lg-side input');
    var side = pair.querySelector('.mu-lg-side input:checked');
    if (!on && side) side.checked = false;
    if (on && !side) sides[0].checked = true;
  });
}

document.addEventListener('DOMContentLoaded', museumLetGoSyncAll);
document.addEventListener('htmx:afterSwap', museumLetGoSyncAll);

document.addEventListener('change', function(e) {
  var form = e.target.closest && e.target.closest('[data-let-go]');
  if (!form) return;
  if (e.target.matches('[data-group-tick]')) museumTickGroup(e.target.closest('.mu-lg-group'), e.target.checked);
  museumLetGoSync(form);
});

document.addEventListener('click', function(e) {
  var fold = e.target.closest('[data-fold]');
  if (!fold) return;
  var folded = fold.closest('.mu-lg-group').classList.toggle('is-folded');
  fold.textContent = folded ? 'Show ▸' : 'Hide ▾';
  fold.setAttribute('aria-expanded', String(!folded));
});

// Ticket Museum promote forms: a new story, or an existing one found by searching.
document.addEventListener('click', function(e) {
  var segment = e.target.closest('[data-segment]');
  if (!segment) return;
  var slot = segment.closest('[data-slot]');
  var which = segment.getAttribute('data-segment');
  slot.querySelectorAll('[data-segment]').forEach(function(one) { one.classList.toggle('is-active', one === segment); });
  slot.querySelectorAll('[data-panel]').forEach(function(panel) { panel.hidden = panel.getAttribute('data-panel') !== which; });
  var search = slot.querySelector('[data-story-search]');
  if (which === 'add') {
    search.focus();
    htmx.trigger(search, 'open-picker');
  } else {
    var title = slot.querySelector('[data-title]');
    if (title) title.focus();
  }
});

// Ticket Museum promote together: × takes an exhibit out of the set, and the
// ticks are finished with once the set is sent.
document.addEventListener('click', function(e) {
  var remove = e.target.closest('[data-remove-exhibit]');
  if (!remove) return;
  e.preventDefault();
  var id = remove.getAttribute('data-remove-exhibit');
  remove.closest('[data-exhibit]').remove();
  document.querySelectorAll('input[name="ids[]"][value="' + id + '"], [data-leaving="' + id + '"]').forEach(function(el) { el.remove(); });
  var exhibits = document.querySelectorAll('[data-exhibit]').length;
  document.querySelector('[data-together-title]').textContent = 'Promote ' + exhibits + (exhibits === 1 ? ' exhibit' : ' exhibits') + ' as one story';
  var promote = document.querySelector('[data-panel="new"] button[type="submit"]');
  if (promote) {
    promote.textContent = 'Promote ' + exhibits + ' as one story';
    promote.setAttribute('data-count', exhibits);
  }
  document.querySelector('[data-add-submit]').textContent = exhibits === 1
    ? 'Add ' + document.querySelector('[data-exhibit]').getAttribute('data-key') + ' to this story'
    : 'Add ' + exhibits + ' exhibits to this story';
  if (exhibits === 1) document.querySelector('[data-remove-exhibit]').hidden = true;
});

document.addEventListener('submit', function(e) {
  var team = e.target.getAttribute('data-clears-selection');
  if (!team) return;
  try { sessionStorage.removeItem('museum-selection:' + team); } catch (err) { /* nothing was kept */ }
});

// Ticket Museum cases: clicking an exhibit's row, or its key from the
// keyboard, opens its whole record underneath, one at a time, with the open
// key kept in the address. Its Promote opens the case ready to type in. Its
// tick box, other buttons and links do their own thing.
document.addEventListener('click', function(e) {
  var row = e.target.closest('.mu-row[data-case]');
  if (!row) return;
  var isOpen = row.classList.contains('is-open');
  if (e.target.closest('.mu-promote')) {
    e.preventDefault();
    if (isOpen) focusMuseumTitle(row);
    else openMuseumCase(row, function() { focusMuseumTitle(row); });
    return;
  }
  if (!e.target.closest('[data-open-case]') && e.target.closest('a, button, input, label, select, form')) return;
  if (isOpen) {
    closeMuseumCase(row);
    keepOpenMuseumCase(null);
  } else {
    openMuseumCase(row);
  }
});

function openMuseumCase(row, opened) {
  document.querySelectorAll('.mu-row.is-open').forEach(closeMuseumCase);
  var list = new URL(window.location.href);
  list.searchParams.delete('open');
  var returnTo = encodeURIComponent(list.pathname + list.search);
  var slot = museumCaseSlot(row);
  htmx.ajax('GET', row.getAttribute('data-case') + '?return_to=' + returnTo, { target: slot, swap: 'innerHTML' }).then(function() {
    if (!slot.firstElementChild) return;
    row.classList.add('is-open');
    row.querySelector('.mu-caret').textContent = '▾';
    row.querySelector('[data-open-case]').setAttribute('aria-expanded', 'true');
    keepOpenMuseumCase(row.getAttribute('data-key'));
    if (opened) opened();
  });
}

function focusMuseumTitle(row) {
  var title = museumCaseSlot(row).querySelector('[data-title]');
  if (title) title.focus();
}

function museumCaseSlot(row) {
  var next = row.nextElementSibling;
  while (next && !next.classList.contains('mu-case-slot')) next = next.nextElementSibling;
  return next;
}

function closeMuseumCase(row) {
  row.classList.remove('is-open');
  row.querySelector('.mu-caret').textContent = '▸';
  row.querySelector('[data-open-case]').setAttribute('aria-expanded', 'false');
  var slot = museumCaseSlot(row);
  if (slot) slot.innerHTML = '';
}

function keepOpenMuseumCase(key) {
  var url = new URL(window.location.href);
  if (key) url.searchParams.set('open', key); else url.searchParams.delete('open');
  history.replaceState(history.state, '', url);
}

// Ticket Museum rewrite form: start from the Jira summary, count the title,
// point out ticket-speak (advice only, never blocking), and add or remove
// scenario cards, keeping them numbered.
var TICKET_SPEAK = [
  { pattern: /^\s*\[(BE|FE|API|DB|QA|UI)\]/i,
    message: function(match) { return '[' + match[1].toUpperCase() + '] is how Jira splits work. Say what changes for the person.'; } },
  { pattern: /^\s*as an? .+? i want( to)?\s*/i,
    message: function() { return '"As a user I want" is ticket-speak. Say what someone can do.'; },
    suggest: function(title, match) {
      var rest = title.slice(match[0].length).replace(/\s*,?\s*so that.*$/i, '').trim();
      return rest ? rest.charAt(0).toUpperCase() + rest.slice(1) : '';
    } },
  { pattern: /^\s*(refactor|upgrade|migrate|bump|clean ?up|tech debt)\b/i,
    message: function() { return 'Sounds like a tech task. Add it to the story it makes possible, or send it to storage.'; } },
  { pattern: /\b(implement|create endpoint|add column)\b/i,
    message: function() { return "That's how it gets built. What does someone get?"; } }
];

function museumRewriteTitle(input) {
  var form = input.closest('[data-rewrite]');
  var counter = form.querySelector('[data-counter]');
  counter.textContent = input.value.length + '/200';
  counter.setAttribute('data-length', input.value.length);
  counter.classList.toggle('is-over', input.value.length > 200);
  clearTimeout(input.ticketSpeakTimer);
  input.ticketSpeakTimer = setTimeout(function() { museumTicketSpeak(input.value, form.querySelector('[data-hint]')); }, 250);
}

function museumTicketSpeak(title, hint) {
  hint.textContent = '';
  for (var i = 0; i < TICKET_SPEAK.length; i++) {
    var rule = TICKET_SPEAK[i];
    var match = title.match(rule.pattern);
    if (!match) continue;
    var mark = document.createElement('span');
    mark.className = 'mu-hint-mark';
    mark.textContent = '!';
    var text = document.createElement('span');
    text.textContent = rule.message(match) + ' ';
    var suggestion = rule.suggest && rule.suggest(title, match);
    if (suggestion) {
      var em = document.createElement('em');
      em.textContent = suggestion;
      text.appendChild(em);
    }
    hint.appendChild(mark);
    hint.appendChild(text);
    hint.hidden = false;
    return;
  }
  hint.hidden = true;
}

function museumNumberScenarios(list) {
  var cards = list.querySelectorAll('[data-scenario]');
  cards.forEach(function(card, index) {
    card.querySelector('[data-scenario-n]').textContent = 'S' + (index + 1);
    card.querySelectorAll('textarea').forEach(function(box) {
      box.name = box.name.replace(/scenarios\[\d+\]/, 'scenarios[' + index + ']');
    });
  });
  var count = list.closest('[data-rewrite]').querySelector('[data-scenario-count]');
  count.textContent = cards.length + (cards.length === 1 ? ' scenario' : ' scenarios');
}

// A story half written in an open case is kept for this tab until it is
// promoted, so opening another exhibit or reloading doesn't lose it.
function museumSaveDraft(form) {
  if (!form) return;
  var scenarios = Array.prototype.map.call(form.querySelectorAll('[data-scenario]'), function(card) {
    return Array.prototype.map.call(card.querySelectorAll('textarea'), function(box) { return box.value; });
  });
  var title = form.querySelector('[data-title]').value;
  var written = title || scenarios.some(function(parts) { return parts.some(Boolean); });
  var draft = { title: title, task_id: form.querySelector('[name="task_id"]').value, scenarios: scenarios };
  try {
    if (written) sessionStorage.setItem(form.getAttribute('data-draft'), JSON.stringify(draft));
    else sessionStorage.removeItem(form.getAttribute('data-draft'));
  } catch (e) { /* kept on this page only */ }
}

function museumReadDraft(form) {
  try { return JSON.parse(sessionStorage.getItem(form.getAttribute('data-draft'))); } catch (e) { return null; }
}

function museumRestoreDraft(form) {
  if (form.draftRestored) return;
  form.draftRestored = true;
  var draft = museumReadDraft(form);
  if (!draft) return;
  var title = form.querySelector('[data-title]');
  title.value = draft.title;
  museumRewriteTitle(title);
  var task = form.querySelector('[name="task_id"]');
  if (task.querySelector('option[value="' + draft.task_id + '"]')) task.value = draft.task_id;
  var list = form.querySelector('[data-scenario-list]');
  var first = list.querySelector('[data-scenario]');
  draft.scenarios.forEach(function(parts, index) {
    var card = index === 0 ? first : list.appendChild(first.cloneNode(true));
    card.querySelectorAll('textarea').forEach(function(box, part) { box.value = parts[part] || ''; });
  });
  museumNumberScenarios(list);
}

function museumRestoreDrafts() {
  document.querySelectorAll('[data-draft]').forEach(museumRestoreDraft);
}

document.addEventListener('DOMContentLoaded', museumRestoreDrafts);
document.addEventListener('htmx:afterSwap', museumRestoreDrafts);

// Promoted in place: the draft is finished with, and the next exhibit on the
// page that can be promoted opens ready to type. A refusal leaves all of it be.
function museumFormInPlace(e) {
  var form = e.detail.requestConfig && e.detail.requestConfig.elt;
  return form && form.matches && form.matches('[data-draft], [data-in-place]') ? form : null;
}

function museumNextKey(form) {
  var rows = Array.prototype.slice.call(document.querySelectorAll('.mu-row[data-case]'));
  var key = form.closest('.mu-case').getAttribute('data-key');
  var after = rows.slice(rows.findIndex(function(row) { return row.getAttribute('data-key') === key; }) + 1);
  var next = after.find(function(row) { return row.querySelector('.mu-promote'); });
  return next && next.getAttribute('data-key');
}

document.addEventListener('htmx:beforeSwap', function(e) {
  var form = museumFormInPlace(e);
  if (!form || !e.detail.serverResponse) return;
  form.promoted = true;
  form.nextKey = museumNextKey(form);
});

document.addEventListener('htmx:afterSwap', function(e) {
  var form = museumFormInPlace(e);
  if (!form || !form.promoted) return;
  var draft = form.getAttribute('data-draft') || form.getAttribute('data-draft-key');
  try { sessionStorage.removeItem(draft); } catch (err) { /* nothing was kept */ }
  keepOpenMuseumCase(null);
  var next = document.querySelector('.mu-row[data-key="' + form.nextKey + '"]');
  if (next) openMuseumCase(next, function() { focusMuseumTitle(next); });
});

document.addEventListener('input', function(e) {
  if (!e.target.closest) return;
  if (e.target.matches('[data-rewrite] [data-title]')) museumRewriteTitle(e.target);
  museumSaveDraft(e.target.closest('[data-draft]'));
});

document.addEventListener('change', function(e) {
  if (e.target.closest) museumSaveDraft(e.target.closest('[data-draft]'));
});

document.addEventListener('click', function(e) {
  var fill = e.target.closest('[data-fill-title]');
  if (fill) {
    var input = fill.closest('[data-rewrite]').querySelector('[data-title]');
    input.value = fill.getAttribute('data-fill-title').slice(0, 200);
    museumRewriteTitle(input);
    museumSaveDraft(input.closest('[data-draft]'));
    input.focus();
    return;
  }
  var add = e.target.closest('[data-add-scenario]');
  if (add) {
    var list = add.closest('[data-rewrite]').querySelector('[data-scenario-list]');
    var card = list.querySelector('[data-scenario]').cloneNode(true);
    card.querySelectorAll('textarea').forEach(function(box) { box.value = ''; });
    list.appendChild(card);
    museumNumberScenarios(list);
    museumSaveDraft(add.closest('[data-draft]'));
    card.querySelector('textarea').focus();
    return;
  }
  var remove = e.target.closest('[data-remove-scenario]');
  if (remove) {
    var scenarios = remove.closest('[data-scenario-list]');
    var one = remove.closest('[data-scenario]');
    if (scenarios.querySelectorAll('[data-scenario]').length > 1) {
      one.remove();
    } else {
      one.querySelectorAll('textarea').forEach(function(box) { box.value = ''; });
    }
    museumNumberScenarios(scenarios);
    museumSaveDraft(scenarios.closest('[data-draft]'));
  }
});
