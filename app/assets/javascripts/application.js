// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, or any plugin's
// vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file. JavaScript code in this file should be added after the last require_* statement.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require rails-ujs
//= require activestorage
//= require turbolinks
//= require cable
//= require_tree .

(function() {
  if (window.Turbolinks && typeof window.Turbolinks.pagesCached === 'function') {
    window.Turbolinks.pagesCached(0);
  }
  document.addEventListener('turbolinks:before-cache', function() {
    document.body.style.overflow = '';
  });
  document.addEventListener('turbo:before-prefetch', function(event) {
    event.preventDefault();
  });
})();

document.addEventListener('DOMContentLoaded', () => {
  const mobileNavToggle = document.getElementById('mobile-nav-toggle');
  const mobileNavMenu = document.getElementById('mobile-nav-menu');
  const mobileNavClose = document.getElementById('mobile-nav-close');

  function closeMobileMenu() {
    mobileNavToggle.classList.remove('active');
    mobileNavMenu.classList.remove('active');
    document.body.style.overflow = '';
  }

  if (mobileNavToggle && mobileNavMenu) {
    mobileNavToggle.addEventListener('click', () => {
      mobileNavToggle.classList.toggle('active');
      mobileNavMenu.classList.toggle('active');

      if (mobileNavMenu.classList.contains('active')) {
        document.body.style.overflow = 'hidden';
      } else {
        document.body.style.overflow = '';
      }
    });

    if (mobileNavClose) {
      mobileNavClose.addEventListener('click', closeMobileMenu);
    }

    const mobileNavLinks = document.querySelectorAll('.mobile-nav-link');
    mobileNavLinks.forEach(link => {
      link.addEventListener('click', closeMobileMenu);
    });

    document.addEventListener('click', (e) => {
      if (!mobileNavToggle.contains(e.target) && !mobileNavMenu.contains(e.target)) {
        closeMobileMenu();
      }
    });
  }
});

const mountDataTargetNav = () => {
  document.body.addEventListener('click', (e) => {
    const a = e.target.closest('a[data-target]');
    if (!a) return;

    e.preventDefault();
    const id = a.getAttribute('data-target');
    const target = document.getElementById(id);
    if (!target) return;

    const headerH = document.querySelector('.site-header')?.offsetHeight || 0;
    const top = target.getBoundingClientRect().top + window.scrollY - headerH - 10;

    window.scrollTo({ top: Math.max(0, Math.round(top)), behavior: 'smooth' });

    setTimeout(() => window.dispatchEvent(new Event('scroll')), 60);
  });
};

if (window.Turbo) document.addEventListener('turbo:load', mountDataTargetNav);
else document.addEventListener('DOMContentLoaded', mountDataTargetNav);

const dismissFlashMessages = () => {
  const flashes = document.querySelectorAll('.flash-message, .admin-flash-message');
  flashes.forEach((flash) => {
    if (flash.dataset.dismissScheduled === 'true') return;
    flash.dataset.dismissScheduled = 'true';
    setTimeout(() => {
      flash.style.transition = 'opacity 0.5s ease';
      flash.style.opacity = '0';
      setTimeout(() => flash.remove(), 500);
    }, 3000);
  });
};

document.addEventListener('turbolinks:load', dismissFlashMessages);
document.addEventListener('DOMContentLoaded', dismissFlashMessages);
document.addEventListener('turbo:load', dismissFlashMessages);
