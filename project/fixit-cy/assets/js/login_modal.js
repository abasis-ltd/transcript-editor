window.LoginModal = {
  show: function() {
    // If isAuthenticated() returns true, do not show the pop-up
    if (window.AuthManager && window.AuthManager.isAuthenticated() === true) {
      return;
    }
    document.getElementById('login-modal-overlay').style.display = 'flex';
  },
  hide: function() {
    document.getElementById('login-modal-overlay').style.display = 'none';
  }
};