/**
 * This script handles all custom functionality for the Fix-it platform,
 * including the profile picture display and the authentication wall for transcripts.
 */

// --- Authentication Wall using Event Delegation ---
// This single event listener is attached to the document body and will catch
// clicks on any element, including those added to the page later.
document.body.addEventListener('click', function(event) {
  // 1) catch any <a class="transcript-item"> click, whether in the page or in a pop-up
  const transcriptLink = event.target.closest('a.transcript-item');
  if (!transcriptLink) return;

  // 2) if the user isn’t signed in, block navigation and show the login modal
  if (window.AuthManager && !window.AuthManager.isAuthenticated()) {
    event.preventDefault();
    console.log('Auth Wall: Unauthenticated click ➔ showing login modal');
    window.LoginModal.show();
  }
  // 3) else: user is authed, link works as normal
});

$(document.body).on('click', '.auth-link', function(e) {
  e.preventDefault();
  var provider = $(this).data('provider');
  $.auth.oAuthSignIn({provider: provider})
    .fail(function(resp) {
      $(window).trigger(
        'alert',
        ['Authentication failure: ' + resp.errors.join(' ')]
      );
    });
});


// --- User Profile Display Logic ---
// This part of the script listens for a successful login and updates the header.
document.addEventListener('auth.status.changed', (event) => {
  if (event.detail.type === 'success' && event.detail.user) {
    const userData = {
      name: event.detail.user.name,
      pictureUrl: event.detail.user.image
    };
    updateUserProfileDisplay(userData);
  }
});

function updateUserProfileDisplay(userData) {
  const userDisplayContainer = document.querySelector('#account-container .select-active');
  if (!userDisplayContainer) {
    return;
  }
  
  userDisplayContainer.innerHTML = '';

  const profileImg = document.createElement('img');
  profileImg.src = userData.pictureUrl;
  profileImg.alt = 'User profile picture';
  profileImg.className = 'user-profile-img';

  const userNameTooltip = document.createElement('span');
  userNameTooltip.textContent = userData.name;
  userNameTooltip.className = 'user-profile-name';
  userNameTooltip.title = userData.name;

  userDisplayContainer.appendChild(profileImg);
  userDisplayContainer.appendChild(userNameTooltip);
}


// --- Profile Dropdown Menu Logic ---
// This handles the click-to-toggle functionality for the user profile menu.
function setupProfileDropdown() {
  const accountContainer = document.getElementById('account-container');
  if (!accountContainer) return;

  accountContainer.addEventListener('click', function(event) {
    const trigger = accountContainer.querySelector('.select-active');
    const dropdown = accountContainer.querySelector('.select-options.account-menu');

    if (trigger && dropdown && trigger.contains(event.target)) {
      dropdown.classList.toggle('show');
    }
  });
}

// Close the dropdown if the user clicks anywhere else on the page.
window.addEventListener('click', function(event) {
  const accountContainer = document.getElementById('account-container');
  if (accountContainer && !accountContainer.contains(event.target)) {
    const dropdown = accountContainer.querySelector('.select-options.account-menu.show');
    if (dropdown) {
      dropdown.classList.remove('show');
    }
  }
});

// Run the dropdown setup once the initial page has loaded.
document.addEventListener('DOMContentLoaded', setupProfileDropdown);
