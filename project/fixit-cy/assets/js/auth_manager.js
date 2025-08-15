window.AuthManager = {
  init: function () {
    this.setupAuthListeners();
    this.setupHashSignIn();
  },

  setupHashSignIn: function () {
    window.addEventListener('hashchange', function () {
      if (window.location.hash === '#sign-in-with-google') {
        // replace hash so user doesn’t get stuck if they hit back()
        window.history.replaceState({}, document.title, window.location.pathname);
        // actually start the Google OAuth dance, with a redirect back home
        window.location.href = '/auth/google?redirect_url=/';
      }
    });
  },
  setupAuthListeners: function () {
    const params = new URLSearchParams(window.location.search);
    const token = params.get('token');
    const clientId = params.get('client_id');
    const uid = params.get('uid');

    if (token && clientId && uid) {
      localStorage.setItem('access-token', token);
      localStorage.setItem('client', clientId);
      localStorage.setItem('uid', uid);
      //window.history.r
      // strip the query string so we don’t re-process tokens in history
      window.history.replaceState({}, document.title, window.location.pathname);
      // finally, send the user to “/” now that they’re authenticated
      window.location.href = '/';
    }
  },

  checkAuthStatus: function () {
    if (localStorage.getItem('access-token')) {
      this.fetchUserProfile();
    } else {
      window.currentUser = { signedIn: false };
      this.updateUIForUnauthenticatedUser();
      this.dispatchAuthEvent('logout');
    }
  },

  fetchUserProfile: function () {
    const headers = {
      'Content-Type': 'application/json',
      'access-token': localStorage.getItem('access-token'),
      'client': localStorage.getItem('client'),
      'uid': localStorage.getItem('uid')
    };

    fetch('/api/v1/profile', { headers: headers })
      .then(response => {
        if (!response.ok) throw new Error('Invalid session');
        return response.json();
      })
      .then(data => {
        window.currentUser = { ...data.user, signedIn: true };
        this.updateUIForAuthenticatedUser(data.user);
        this.dispatchAuthEvent('success');
      })
      .catch(() => {
        this.signOut(false);
      });
  },

  updateUIForAuthenticatedUser: function (user) {
    const profileIcon = document.getElementById('profileIcon');
    const dropdownMenu = document.getElementById('dropdownMenu');

    if (profileIcon && user.image) {
      profileIcon.innerHTML = `<img src="${user.image}" alt="${user.name}" class="profile-icon user-avatar">`;
    }

    if (dropdownMenu) {
      dropdownMenu.innerHTML = `
        <a href="/dashboard" class="dropdown-item">Dashboard</a>
        <a href="/profile" class="dropdown-item">Profile</a>
        <a href="#" onclick="AuthManager.signOut()" class="dropdown-item">Sign Out</a>
      `;
    }
  },

  updateUIForUnauthenticatedUser: function () {
    const profileIcon = document.getElementById('profileIcon');
    const dropdownMenu = document.getElementById('dropdownMenu');

    if (profileIcon) {
      profileIcon.innerHTML = `<img src="/assets/profile-circle.svg" alt="Profile icon" class="profile-icon">`;
    }

    if (dropdownMenu) {
      dropdownMenu.innerHTML = `
        <div style="padding: 10px;">
          <a href="/auth/google_oauth2" class="google-signin-btn">
            <img src="/assets/google-icon.svg" alt="Google icon">
            <span>Sign in with Google</span>
          </a>
        </div>
      `;
    }
  },

  signOut: function (shouldRedirect = true) {
    localStorage.removeItem('access-token');
    localStorage.removeItem('client');
    localStorage.removeItem('uid');
    window.currentUser = { signedIn: false };
    this.updateUIForUnauthenticatedUser();
    this.dispatchAuthEvent('logout');
    if (shouldRedirect) {
      window.location.href = '/';
    }
  },

  isAuthenticated: function() {
    // If you use j-toker, $.auth.user will be set on successful login
    if (window.$ && $.auth && $.auth.user && $.auth.user.id) {
      return true;
    }
    // Fallback to token-in-localStorage
    return !!localStorage.getItem('access-token');
  },

  dispatchAuthEvent: function (type) {
    document.dispatchEvent(new CustomEvent('auth.status.changed', {
      detail: { type: type, user: window.currentUser }
    }));
  }
};

document.addEventListener('DOMContentLoaded', () => AuthManager.init());