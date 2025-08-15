window.Profile = {
  init: function() {
    document.addEventListener('auth.status.changed', (event) => {
      if (event.detail.type === 'success') {
        // The AuthManager already fetched the profile, so we can just render it.
        this.render(event.detail.user);
      }
    });
  },

  render: function(user) {
    const nameElement = document.getElementById('profile-name');
    if (nameElement) {
      nameElement.textContent = user.name;
    }
    // You would add more rendering logic here.
    console.log('Rendered Profile Page for:', user.name);
  }
};

if (window.location.pathname.includes('/profile')) {
  document.addEventListener('DOMContentLoaded', () => window.Profile.init());
}