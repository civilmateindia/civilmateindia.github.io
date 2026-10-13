/**
 * CivilMate - Universal Mobile Navigation & Header Menu Handler
 * Handles responsive hamburger drawer, mobile dropdowns, and tap-outside dismissals.
 */

function toggleMobileNav() {
    const navLinks = document.getElementById('navLinks') || document.querySelector('.nav-links');
    const menuBtn = document.getElementById('mobileMenuBtn') || document.querySelector('.mobile-menu-btn');
    if (!navLinks) return;

    const isOpen = navLinks.classList.toggle('active');
    if (menuBtn) {
        menuBtn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
        const icon = menuBtn.querySelector('.material-icons');
        if (icon) {
            icon.textContent = isOpen ? 'close' : 'menu';
        }
    }
}

function toggleMobileDropdown(e) {
    if (window.innerWidth <= 768) {
        if (e) {
            e.preventDefault();
            e.stopPropagation();
        }
        const dropdown = (e && e.currentTarget) ? e.currentTarget.closest('.dropdown') : document.querySelector('.dropdown');
        if (dropdown) {
            dropdown.classList.toggle('mobile-open');
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    const menuBtn = document.getElementById('mobileMenuBtn') || document.querySelector('.mobile-menu-btn');
    const navLinks = document.getElementById('navLinks') || document.querySelector('.nav-links');

    if (menuBtn && !menuBtn.getAttribute('onclick')) {
        menuBtn.addEventListener('click', toggleMobileNav);
    }

    // Auto-close menu when a link inside is clicked (excluding parent dropdown toggle)
    if (navLinks) {
        navLinks.querySelectorAll('a').forEach(link => {
            if (!link.parentElement.classList.contains('dropdown') || link.parentElement.classList.contains('dropdown-content')) {
                link.addEventListener('click', () => {
                    if (window.innerWidth <= 768 && navLinks.classList.contains('active')) {
                        toggleMobileNav();
                    }
                });
            }
        });
    }

    // Close mobile nav when clicking anywhere outside
    document.addEventListener('click', (e) => {
        if (window.innerWidth <= 768 && navLinks && navLinks.classList.contains('active')) {
            const isClickInsideNav = navLinks.contains(e.target);
            const isClickOnToggle = menuBtn && menuBtn.contains(e.target);
            if (!isClickInsideNav && !isClickOnToggle) {
                toggleMobileNav();
            }
        }
    });

    // Auto-close menu if resized back to desktop
    window.addEventListener('resize', () => {
        if (window.innerWidth > 768 && navLinks && navLinks.classList.contains('active')) {
            navLinks.classList.remove('active');
            if (menuBtn) {
                const icon = menuBtn.querySelector('.material-icons');
                if (icon) icon.textContent = 'menu';
            }
        }
    });
});
