window.Dashboard = {
  init: function() {
    document.addEventListener('auth.status.changed', (event) => {
      if (event.detail.type === 'success') {
        this.fetchDashboardData();
      }
    });
  },

  fetchDashboardData: function() {
    const headers = {
      'Content-Type': 'application/json',
      'access-token': localStorage.getItem('access-token'),
      'client': localStorage.getItem('client'),
      'uid': localStorage.getItem('uid')
    };

    fetch('/api/v1/dashboard_data', { headers: headers })
      .then(response => response.json())
      .then(data => {
        // You would write a function here to render the data
        console.log('Dashboard Data:', data);
      });
  }
};

if (window.location.pathname.includes('/dashboard')) {
  document.addEventListener('DOMContentLoaded', () => window.Dashboard.init());
}