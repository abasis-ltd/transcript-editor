document.addEventListener('DOMContentLoaded', function() {
  document.body.addEventListener('click', function(event) {
    const target = event.target.closest('[data-auth-required]');
    if (!target) return;

    if (!(window.AuthManager && window.AuthManager.isAuthenticated())) {
      event.preventDefault();
      window.LoginModal && window.LoginModal.show();
    }
    // if authenticated, do nothing—click proceeds normally
  }, true);
});