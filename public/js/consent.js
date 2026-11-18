// Once the person has answered, both buttons are held, so the answer can't be
// sent twice. They are held a moment after the form goes, because a held
// button's own value, which is the answer, is left out of what is sent.
document.addEventListener('submit', function(e) {
  if (e.defaultPrevented) return;
  var buttons = e.target.querySelectorAll('button[type="submit"]');
  setTimeout(function() {
    buttons.forEach(function(button) { button.disabled = true; });
  }, 0);
});

// Coming back to the page with the browser's back button, the buttons work again.
window.addEventListener('pageshow', function(e) {
  if (!e.persisted) return;
  document.querySelectorAll('button[type="submit"]').forEach(function(button) { button.disabled = false; });
});
