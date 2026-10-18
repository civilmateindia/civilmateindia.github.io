# CivilMate Chrome Extension Update: Complete Architecture & Implementation Guide

> **Target Extension Directory**: `C:\Users\laksh\Desktop\CivilMate Extn - AG\CivilMate_v1.2`  
> **Manifest Version**: Manifest V3  
> **Backend Integration**: Supabase Cloud (`staged_exports`, `staged_imports`, and Supabase Auth)  
> **Authentication Modes**: Google OAuth & Email/Password with Persistent Storage

---

## 1. Executive Overview & Purpose

CivilMate connects civil engineers and contractors between **Google Sheets™ (via Google Workspace Add-on)** and the **Haryana Engineering Works Portal (HEWP: `works.haryana.gov.in`)** using this Chrome/Edge Extension.

Previously, data transfer operated exclusively via a **manual copy-paste clipboard bridge**. We have built a high-speed cloud staging and authentication pipeline in Supabase so that data flows seamlessly between the Add-on and the Extension without relying on clipboard permissions or manual intervention:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              CIVILMATE DUAL-STREAM DATA PIPELINE                       │
└────────────────────────────────────────────────────────────────────────────────────────┘

  STREAM 1: OUTBOUND PIPELINE (Google Sheets ──► Extension ──► HEWP Upload)
  ────────────────────────────────────────────────────────────────────────
  1. User prepares an Estimate or Bill in Google Sheets with the CivilMate Add-on.
  2. Clicking "Export for HEWP" pushes structured JSON to Supabase table: `public.staged_exports`.
     - Categorized by sheet tab name: `doc_type = 'Estimate'` or `doc_type = 'Bill'`.
  3. Chrome Extension authenticates the engineer and queries recent exports for their email.
  4. Separate tabs in the Extension:
     - 📁 "Estimates" tab (`#sectionUpload`): Lists only `doc_type = 'Estimate'` packages.
     - 📁 "Bills" tab (`#sectionBills`): Lists only `doc_type = 'Bill'` packages.
  5. User selects a package and clicks "Load Package". The items populate the automation queue (`allItems`), checked and ready for upload to HEWP.

  STREAM 2: INBOUND PIPELINE (HEWP PDFs ──► Extension ──► Supabase ──► Google Sheets)
  ──────────────────────────────────────────────────────────────────────────────────
  1. Extension's "Extract" tab (`#sectionExtract`) parses two PDF types:
     - 📄 Detailed BoQ PDFs (Published tenders from HEWP live tenders page).
     - 📄 Detailed Estimate PDFs (Engineer login on HEWP with hierarchical measurement sheets).
  2. The parsed JSON data can now be staged directly to Supabase table: `public.staged_imports`.
  3. The Google Sheets Add-on reads this cloud table (or user uses 1-click clipboard copy as offline fallback) to import the data into formatted sheets.
```

---

## 2. Supabase Cloud Configuration & API Credentials

The extension connects to the existing CivilMate Supabase project:

```javascript
const SUPABASE_CONFIG = {
  url: "https://qizuppfogzugazpvvaxg.supabase.co",
  anonKey: "sb_publishable_rWs1g0hoacGIjeorJCfNqw__B_ztAUG"
};
```

---

## 3. Database Schemas & Exact Data Payloads

### A. Table: `public.staged_exports` (Outbound from Sheets to Extension)

| Column Name | Type | Description |
|---|---|---|
| `id` | `uuid` | Primary Key (`gen_random_uuid()`) |
| `user_email` | `text` | Lowercase registered estimator email |
| `work_name` | `text` | Name of the work or package |
| `doc_type` | `text` | `'Estimate'`, `'Bill'`, or `'BoQ'` |
| `status` | `text` | Default `'Ready for HEWP'` |
| `details` | `jsonb` | Complete structured items payload (see schema below) |
| `created_at` | `timestamptz` | Generation timestamp in UTC |

#### Outbound Payload Schema (`details` column):
Hierarchical array of component groups:
```json
[
  {
    "main_comp": "Civil Works",
    "sub_comp": "Substructure",
    "items": [
      {
        "type": "HSR",
        "hsr_no": "6.33.3",
        "rate_type": "Through Rate",
        "desc": "Earth work in excavation in trenches...",
        "total_qty": "125.00",
        "child_rows": [
          {
            "desc": "Foundation pit 1",
            "no": "2",
            "l": "10.00",
            "b": "5.00",
            "d": "1.25",
            "qty": "125.00"
          }
        ]
      },
      {
        "type": "NS",
        "hsr_no": "NS",
        "rate_type": "NS",
        "desc": "Non-scheduled waterproofing membrane",
        "total_qty": "50.00",
        "child_rows": []
      }
    ]
  }
]
```

---

### B. Table: `public.staged_imports` (Inbound from Extension to Sheets)

| Column Name | Type | Description |
|---|---|---|
| `id` | `uuid` | Primary Key (`gen_random_uuid()`) |
| `user_email` | `text` | Lowercase registered estimator email |
| `work_name` | `text` | Tender / Work Name extracted from PDF |
| `doc_type` | `text` | `'BoQ'` or `'Detailed Estimate'` |
| `status` | `text` | Default `'Ready for Sheets'` |
| `details` | `jsonb` | Extracted array of items (see schemas below) |
| `created_at` | `timestamptz` | Extraction timestamp in UTC |

#### Inbound Payload Schema 1: Detailed BoQ (`doc_type = 'BoQ'`):
```json
[
  {
    "documentType": "Detailed BoQ from HEWP Live Tenders",
    "workName": "Construction of Community Center at Ward 5",
    "component": "Civil Works",
    "subComponent": "Building",
    "srNo": 1,
    "type": "HSR",
    "itemNo": "6.33.3",
    "rateType": "Through Rate",
    "description": "Earth work excavation in trenches...",
    "unit": "Cum",
    "totalQty": "125.00"
  }
]
```

#### Inbound Payload Schema 2: Detailed Estimate (`doc_type = 'Detailed Estimate'`):
```json
[
  {
    "documentType": "Detailed Estimate",
    "workName": "Const. of Shed for solid waste management at village - Pobala",
    "component": "Const. of Shed for solid waste management at village - Pobala",
    "subComponent": "Const. of Shed for solid waste management at village - Pobala",
    "srNo": "1",
    "type": "HSR",
    "itemNo": "4.14.1",
    "rateType": "Through Rate",
    "description": "Earth work in excavation by mechanical means (Hydraulic excavator) / manual means in foundation trenches or drains (not exceeding 1.5 m in width or 10 sqm on plan), including dressing of sides and ramming of bottoms, lift up to 1.5 m, including getting out the excavated soil and disposal of surplus excavated soil as directed, within a lead of 50 m. 1. All kinds of soil.",
    "unit": "cum",
    "quantity": "17.584",
    "rate": "93.00",
    "amount": "1635",
    "children": [
      {
        "description": "Long walls",
        "no": "2.00",
        "qty": "",
        "length": "10.668",
        "breadth": "0.610",
        "depth": "0.533",
        "totalQty": "6.938"
      },
      {
        "description": "Short walls",
        "no": "2.00",
        "qty": "",
        "length": "6.248",
        "breadth": "0.610",
        "depth": "0.533",
        "totalQty": "4.063"
      },
      {
        "description": "Soakage pit = 3.1427x0.84x0.84x1.22\n= 2.70 cum",
        "no": "1.00",
        "qty": "",
        "length": "1.000",
        "breadth": "1.000",
        "depth": "2.700",
        "totalQty": "2.700"
      }
    ]
  }
]
```

---

## 4. Authentication Architecture: Google Auth & Email/Password System

The user does **not** need to log in every time. Once authenticated, the session is securely stored in `chrome.storage.local` and persists across browser sessions and extension reloads, with automatic silent refresh when the JWT expires.

### 4.1 Authentication Options
1. **Google OAuth (One-Click)**:
   - Uses Chrome's standard Manifest V3 OAuth API: `chrome.identity.launchWebAuthFlow`.
   - Opens an isolated Google sign-in window.
   - Redirects back to the extension with access & refresh tokens from Supabase Auth.
2. **Email & Password**:
   - Built natively using the Supabase REST Auth API: `POST /auth/v1/token?grant_type=password`.
   - Requires zero popup windows or redirect URIs. Works directly within the popup interface.
3. **Web Portal Session Sync (Zero-Setup Bridge)**:
   - If the user is already logged in to `civilmateindia.github.io/portal.html`, the extension can import that active session with a single click.
4. **Offline / Guest Mode**:
   - If unauthenticated or offline, users can still use clipboard-based features ("Paste & Load" and "Copy Extracted Data").

### 4.2 Supabase Dashboard Configuration for Google OAuth
In the **Supabase Dashboard** &rarr; **Authentication** &rarr; **URL Configuration** &rarr; **Redirect URLs**:
1. Get your extension ID from `chrome://extensions` (e.g. `abcdefghijklmnop...`).
2. Add your extension redirect URL:
   ```
   https://<EXTENSION_ID>.chromiumapp.org/
   ```
   *(You can also find this programmatically by running `chrome.identity.getRedirectURL()` in the extension console).*

---

## 5. Step-by-Step Implementation Instructions for Antigravity

### Step 1: Update `manifest.json`

Add `"identity"` to permissions and include Supabase in `host_permissions`:

```json
{
  "manifest_version": 3,
  "name": "CivilMate: HEWP Workflow Automator",
  "version": "1.7.0",
  "description": "Automated data upload and extraction on works.haryana.gov.in",
  "permissions": [
    "storage",
    "clipboardRead",
    "identity"
  ],
  "host_permissions": [
    "https://works.haryana.gov.in/*",
    "https://*.supabase.co/*",
    "https://civilmateindia.github.io/*"
  ]
}
```

---

### Step 2: Add Auth UI & Staging Controls to `popup.html`

#### A. Add Auth Styles to `<style>` in `popup.html`:
```css
/* --- CLOUD AUTH BAR & MODAL STYLES --- */
.auth-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 12px;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    font-size: 11px;
}
.auth-user-info {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 1;
    overflow: hidden;
}
.user-avatar-badge {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--primary);
    color: var(--btn-text);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 11px;
    flex-shrink: 0;
}
.user-email-text {
    font-weight: 500;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 190px;
}
.cloud-pill {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 10px;
    color: var(--success);
    font-weight: 600;
}
.pulse-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--success);
    box-shadow: 0 0 6px var(--success);
}
.btn-auth-sm {
    padding: 3px 8px;
    font-size: 11px;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 4px;
    color: var(--text);
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 4px;
}
.btn-auth-sm:hover {
    background: var(--hover-bg);
}

/* Modal Overlay */
.auth-modal-overlay {
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0, 0, 0, 0.7);
    z-index: 9999;
    display: flex;
    align-items: center;
    justify-content: center;
    backdrop-filter: blur(2px);
}
.auth-modal-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 12px;
    width: 340px;
    padding: 18px;
    box-shadow: 0 8px 24px var(--shadow);
    display: flex;
    flex-direction: column;
    gap: 12px;
}
.auth-modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
}
.auth-modal-header h3 {
    margin: 0;
    font-size: 15px;
    font-weight: 700;
    color: var(--text);
}
.auth-close-btn {
    background: none;
    border: none;
    font-size: 20px;
    color: var(--subtext);
    cursor: pointer;
}
.auth-close-btn:hover { color: var(--text); }

/* Google OAuth Button */
.btn-google {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    background: #ffffff;
    color: #3c4043;
    border: 1px solid #dadce0;
    border-radius: 6px;
    padding: 9px 12px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s, box-shadow 0.15s;
    width: 100%;
    box-sizing: border-box;
}
.btn-google:hover {
    background: #f8f9fa;
    box-shadow: 0 1px 3px rgba(60,64,67,0.3);
}

.auth-divider {
    display: flex;
    align-items: center;
    text-align: center;
    color: var(--outline);
    font-size: 11px;
}
.auth-divider::before, .auth-divider::after {
    content: '';
    flex: 1;
    border-bottom: 1px solid var(--border);
}
.auth-divider span {
    padding: 0 8px;
}

.auth-field {
    display: flex;
    flex-direction: column;
    gap: 4px;
}
.auth-field label {
    font-size: 11px;
    font-weight: 600;
    color: var(--subtext);
}
.auth-field input {
    background: var(--surface);
    border: 1px solid var(--border);
    color: var(--text);
    border-radius: 6px;
    padding: 8px 10px;
    font-size: 12px;
    outline: none;
}
.auth-field input:focus {
    border-color: var(--primary);
}
.auth-msg-box {
    font-size: 11px;
    padding: 6px 10px;
    border-radius: 6px;
    display: none;
}
.auth-msg-error {
    background: var(--fail-bg);
    color: var(--danger);
    border: 1px solid var(--danger);
}
.auth-msg-success {
    background: var(--card-bg);
    color: var(--success);
    border: 1px solid var(--success);
}
```

#### B. Insert Auth Bar immediately below the `.header` in `popup.html`:
```html
<!-- AUTH STATUS BAR -->
<div class="auth-bar" id="authBar">
    <div id="authLoggedInState" class="auth-user-info" style="display: none;">
        <div class="user-avatar-badge" id="authUserAvatar">E</div>
        <div style="display: flex; flex-direction: column; min-width: 0;">
            <span class="user-email-text" id="authDisplayEmail">engineer@civilmate.in</span>
            <span class="cloud-pill"><span class="pulse-dot"></span> Cloud Connected</span>
        </div>
    </div>
    <div id="authLoggedOutState" class="auth-user-info">
        <span class="material-icons" style="font-size: 16px; color: var(--subtext);">cloud_off</span>
        <span style="color: var(--subtext); font-size: 11px;">Guest / Offline Mode</span>
    </div>
    <div>
        <button id="btnOpenAuthModal" class="btn-auth-sm">
            <span class="material-icons" style="font-size: 14px;">login</span>
            <span>Sign In</span>
        </button>
        <button id="btnAuthSignOut" class="btn-auth-sm" style="display: none;" title="Sign Out">
            <span class="material-icons" style="font-size: 14px;">logout</span>
        </button>
    </div>
</div>
```

#### C. Insert Auth Modal before `</body>` in `popup.html`:
```html
<!-- AUTH MODAL -->
<div id="authModal" class="auth-modal-overlay" style="display: none;">
    <div class="auth-modal-card">
        <div class="auth-modal-header">
            <div style="display: flex; align-items: center; gap: 8px;">
                <img src="icons/48.png" style="width: 20px; height: 20px; border-radius: 4px;">
                <h3>Sign In to CivilMate Cloud</h3>
            </div>
            <button id="btnCloseAuthModal" class="auth-close-btn">&times;</button>
        </div>

        <!-- Google OAuth Button -->
        <button id="btnGoogleSignIn" class="btn-google">
            <svg width="18" height="18" viewBox="0 0 18 18">
                <path fill="#4285F4" d="M17.64 9.2c0-.63-.06-1.25-.16-1.84H9v3.49h4.84a4.14 4.14 0 0 1-1.8 2.71v2.26h2.91c1.7-1.57 2.69-3.88 2.69-6.62z"/>
                <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.91-2.26c-.8.54-1.83.87-3.05.87-2.34 0-4.33-1.58-5.04-3.71H.96v2.33C2.44 15.98 5.48 18 9 18z"/>
                <path fill="#FBBC05" d="M3.96 10.72a5.41 5.41 0 0 1 0-3.44V4.95H.96a9.01 9.01 0 0 0 0 8.1l3-2.33z"/>
                <path fill="#EA4335" d="M9 3.58c1.32 0 2.51.45 3.44 1.35l2.58-2.59C13.46.89 11.43 0 9 0 5.48 0 2.44 2.02.96 4.95l3 2.33c.71-2.13 2.7-3.7 5.04-3.7z"/>
            </svg>
            <span>Continue with Google</span>
        </button>

        <div class="auth-divider">
            <span>or sign in with email</span>
        </div>

        <!-- Email & Password Form -->
        <div class="auth-field">
            <label for="authInputEmail">Registered Email</label>
            <input type="email" id="authInputEmail" placeholder="engineer@domain.com" autocomplete="email">
        </div>
        <div class="auth-field">
            <label for="authInputPassword">Password</label>
            <input type="password" id="authInputPassword" placeholder="••••••••" autocomplete="current-password">
        </div>

        <div id="authMessageBox" class="auth-msg-box"></div>

        <button id="btnEmailSignIn" class="action-btn btn-filled" style="justify-content: center; padding: 10px;">
            <span class="material-icons">login</span>
            <span class="btn-title">Sign In</span>
        </button>

        <!-- Zero-Setup Portal Sync Button -->
        <button id="btnSyncFromPortal" class="action-btn" style="justify-content: center; font-size: 11px; padding: 6px;">
            <span class="material-icons" style="font-size: 15px;">sync</span>
            <span>Sync Session from Web Portal Tab</span>
        </button>

        <div style="display: flex; justify-content: space-between; font-size: 11px; color: var(--subtext); margin-top: 4px;">
            <a href="https://civilmateindia.github.io/portal.html" target="_blank" style="color: var(--primary); text-decoration: none;">New user? Sign Up</a>
            <a href="https://civilmateindia.github.io/portal.html" target="_blank" style="color: var(--subtext); text-decoration: none;">Forgot Password?</a>
        </div>
    </div>
</div>
```

#### D. In `#sectionUpload` (Estimates Tab):
Add the Cloud Staged Estimate selector:
```html
<div class="card" style="margin-bottom: 8px;">
    <div style="font-size: 11px; font-weight: 700; color: var(--outline); text-transform: uppercase; margin-bottom: 6px;">
        Cloud Staged Estimates (from Google Sheets)
    </div>
    <div style="display: flex; gap: 6px; align-items: center;">
        <select id="selectStagedEstimate" style="flex: 1; padding: 7px 10px; border-radius: 6px; border: 1px solid var(--border); font-size: 12px; background: var(--surface); color: var(--text);">
            <option value="">Sign in to view staged estimates...</option>
        </select>
        <button id="btnRefreshStagedEstimates" title="Refresh exports from cloud" style="background: none; border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; cursor: pointer; color: var(--text);">
            <span class="material-icons" style="font-size: 16px;">sync</span>
        </button>
    </div>
    <button id="btnLoadStagedEstimate" class="action-btn btn-filled" style="margin-top: 8px; justify-content: center; padding: 8px;" disabled>
        <span class="material-icons" style="font-size: 18px;">cloud_download</span>
        <span class="btn-title">Load Selected Estimate</span>
    </button>
</div>
```

#### E. In `#sectionBills` (Bills Tab):
Add the Cloud Staged Bill selector:
```html
<div class="card" style="margin-bottom: 8px;">
    <div style="font-size: 11px; font-weight: 700; color: var(--outline); text-transform: uppercase; margin-bottom: 6px;">
        Cloud Staged Bills (from Google Sheets)
    </div>
    <div style="display: flex; gap: 6px; align-items: center;">
        <select id="selectStagedBill" style="flex: 1; padding: 7px 10px; border-radius: 6px; border: 1px solid var(--border); font-size: 12px; background: var(--surface); color: var(--text);">
            <option value="">Sign in to view staged bills...</option>
        </select>
        <button id="btnRefreshStagedBills" title="Refresh exports from cloud" style="background: none; border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; cursor: pointer; color: var(--text);">
            <span class="material-icons" style="font-size: 16px;">sync</span>
        </button>
    </div>
    <button id="btnLoadStagedBill" class="action-btn btn-filled" style="margin-top: 8px; justify-content: center; padding: 8px;" disabled>
        <span class="material-icons" style="font-size: 18px;">cloud_download</span>
        <span class="btn-title">Load Selected Bill</span>
    </button>
</div>
```

#### F. In `#sectionExtract` (Extract Tab):
In the bottom export action buttons, add the **"Stage to CivilMate Cloud"** button:
```html
<button id="btnStageExtractToCloud" class="action-btn btn-filled" style="background-color: var(--success); margin-top: 6px;" disabled>
    <span class="material-icons">cloud_upload</span>
    <div class="btn-text-wrapper" style="align-items: center;">
        <span class="btn-title">Stage to CivilMate Cloud</span>
        <span class="btn-subtext">Direct sync to Google Sheets Add-on</span>
    </div>
</button>
```

---

### Step 3: Implement Full Auth & Staging Logic in `popup.js`

Add the following self-contained module to `popup.js`:

```javascript
// =============================================================================
// CIVILMATE CLOUD AUTHENTICATION & STAGING MODULE
// =============================================================================

const SUPABASE_CONFIG = {
    url: "https://qizuppfogzugazpvvaxg.supabase.co",
    anonKey: "sb_publishable_rWs1g0hoacGIjeorJCfNqw__B_ztAUG"
};

// ================= 1. SESSION MANAGEMENT & PERSISTENCE =================

/**
 * Retrieves the currently active authenticated session.
 * Automatically checks token expiration and performs silent refresh if needed.
 */
async function getValidSession() {
    const data = await chrome.storage.local.get(['civilmateAuthSession']);
    const session = data.civilmateAuthSession;
    if (!session || !session.access_token) return null;

    // Check if token expires within the next 2 minutes
    const now = Date.now();
    if (session.expires_at && now > (session.expires_at - 120000)) {
        if (session.refresh_token) {
            console.log("CivilMate: Access token expiring soon, refreshing...");
            return await refreshAuthSession(session.refresh_token);
        }
        return null;
    }
    return session;
}

/**
 * Silently refreshes the user's JWT access token using the refresh_token.
 */
async function refreshAuthSession(refreshToken) {
    try {
        const res = await fetch(`${SUPABASE_CONFIG.url}/auth/v1/token?grant_type=refresh_token`, {
            method: 'POST',
            headers: {
                'apikey': SUPABASE_CONFIG.anonKey,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ refresh_token: refreshToken })
        });
        if (!res.ok) {
            console.warn("Token refresh failed. User must sign in again.");
            await chrome.storage.local.remove(['civilmateAuthSession']);
            updateAuthUI(null);
            return null;
        }

        const data = await res.json();
        const updatedSession = {
            access_token: data.access_token,
            refresh_token: data.refresh_token,
            expires_at: Date.now() + (data.expires_in * 1000),
            user: data.user
        };
        await chrome.storage.local.set({ civilmateAuthSession: updatedSession });
        updateAuthUI(updatedSession);
        return updatedSession;
    } catch (e) {
        console.error("Token refresh error:", e);
        return null;
    }
}

/**
 * Updates the extension UI (auth bar, avatars, and dropdowns) based on session state.
 */
function updateAuthUI(session) {
    const loggedInState = document.getElementById('authLoggedInState');
    const loggedOutState = document.getElementById('authLoggedOutState');
    const displayEmail = document.getElementById('authDisplayEmail');
    const userAvatar = document.getElementById('authUserAvatar');
    const btnOpenAuth = document.getElementById('btnOpenAuthModal');
    const btnSignOut = document.getElementById('btnAuthSignOut');

    if (session && session.user && session.user.email) {
        if (loggedInState) loggedInState.style.display = 'flex';
        if (loggedOutState) loggedOutState.style.display = 'none';
        if (btnOpenAuth) btnOpenAuth.style.display = 'none';
        if (btnSignOut) btnSignOut.style.display = 'inline-flex';

        const email = session.user.email;
        if (displayEmail) displayEmail.textContent = email;
        if (userAvatar) userAvatar.textContent = email.charAt(0).toUpperCase();
    } else {
        if (loggedInState) loggedInState.style.display = 'none';
        if (loggedOutState) loggedOutState.style.display = 'flex';
        if (btnOpenAuth) btnOpenAuth.style.display = 'inline-flex';
        if (btnSignOut) btnSignOut.style.display = 'none';
    }
}

// ================= 2. SIGN IN: EMAIL & PASSWORD =================

async function signInWithEmailPassword(email, password) {
    const msgBox = document.getElementById('authMessageBox');
    const signInBtn = document.getElementById('btnEmailSignIn');

    if (!email || !password) {
        showAuthMessage("Please enter both email and password.", "error");
        return;
    }

    if (signInBtn) {
        signInBtn.disabled = true;
        signInBtn.innerHTML = '<span class="material-icons rotating">autorenew</span> Signing In...';
    }

    try {
        const res = await fetch(`${SUPABASE_CONFIG.url}/auth/v1/token?grant_type=password`, {
            method: 'POST',
            headers: {
                'apikey': SUPABASE_CONFIG.anonKey,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                email: email.trim().toLowerCase(),
                password: password
            })
        });

        const data = await res.json();
        if (!res.ok) {
            throw new Error(data.error_description || data.message || "Invalid email or password.");
        }

        const session = {
            access_token: data.access_token,
            refresh_token: data.refresh_token,
            expires_at: Date.now() + (data.expires_in * 1000),
            user: data.user
        };

        await chrome.storage.local.set({ civilmateAuthSession: session });
        updateAuthUI(session);
        closeAuthModal();

        // Automatically trigger cloud fetch for active tab
        refreshActiveTabExports();

    } catch (err) {
        showAuthMessage(err.message, "error");
    } finally {
        if (signInBtn) {
            signInBtn.disabled = false;
            signInBtn.innerHTML = '<span class="material-icons">login</span><span class="btn-title">Sign In</span>';
        }
    }
}

// ================= 3. SIGN IN: GOOGLE OAUTH =================

async function signInWithGoogle() {
    const redirectUri = chrome.identity.getRedirectURL(); // e.g. https://<ext-id>.chromiumapp.org/
    const authUrl = `${SUPABASE_CONFIG.url}/auth/v1/authorize?provider=google&redirect_to=${encodeURIComponent(redirectUri)}`;

    showAuthMessage("Opening Google Sign-In...", "success");

    chrome.identity.launchWebAuthFlow({
        url: authUrl,
        interactive: true
    }, async (responseUrl) => {
        if (chrome.runtime.lastError || !responseUrl) {
            const errMsg = chrome.runtime.lastError?.message || "Google sign-in was cancelled.";
            showAuthMessage(errMsg, "error");
            return;
        }

        try {
            // The responseUrl contains hash fragments: #access_token=...&refresh_token=...&expires_in=...
            const url = new URL(responseUrl);
            const hashParams = new URLSearchParams(url.hash.substring(1));

            const accessToken = hashParams.get('access_token');
            const refreshToken = hashParams.get('refresh_token');
            const expiresIn = parseInt(hashParams.get('expires_in') || '3600', 10);

            if (!accessToken) {
                throw new Error("No access token returned from Google authorization.");
            }

            // Fetch user profile from Supabase
            const userRes = await fetch(`${SUPABASE_CONFIG.url}/auth/v1/user`, {
                headers: {
                    'apikey': SUPABASE_CONFIG.anonKey,
                    'Authorization': `Bearer ${accessToken}`
                }
            });

            if (!userRes.ok) throw new Error("Could not retrieve user profile.");
            const userData = await userRes.json();

            const session = {
                access_token: accessToken,
                refresh_token: refreshToken,
                expires_at: Date.now() + (expiresIn * 1000),
                user: userData
            };

            await chrome.storage.local.set({ civilmateAuthSession: session });
            updateAuthUI(session);
            closeAuthModal();

            refreshActiveTabExports();

        } catch (err) {
            showAuthMessage(err.message, "error");
        }
    });
}

// ================= 4. SIGN IN: SYNC FROM WEB PORTAL TAB (ZERO SETUP) =================

async function syncSessionFromPortalTab() {
    showAuthMessage("Checking open CivilMate portal tabs...", "success");
    try {
        const tabs = await chrome.tabs.query({ url: "*://civilmateindia.github.io/*" });
        if (!tabs || tabs.length === 0) {
            showAuthMessage("Please open & log in to portal.html in Chrome first.", "error");
            return;
        }

        // Execute script in the open portal tab to extract supabase auth token from localStorage
        const result = await chrome.scripting.executeScript({
            target: { tabId: tabs[0].id },
            func: () => {
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key && key.includes('auth-token')) {
                        return localStorage.getItem(key);
                    }
                }
                return null;
            }
        });

        const rawSession = result[0]?.result;
        if (!rawSession) {
            showAuthMessage("No active session found in the portal tab. Please sign in there.", "error");
            return;
        }

        const parsed = JSON.parse(rawSession);
        const session = {
            access_token: parsed.access_token,
            refresh_token: parsed.refresh_token,
            expires_at: parsed.expires_at ? (parsed.expires_at * 1000) : (Date.now() + 3600000),
            user: parsed.user
        };

        await chrome.storage.local.set({ civilmateAuthSession: session });
        updateAuthUI(session);
        closeAuthModal();
        refreshActiveTabExports();

    } catch (err) {
        showAuthMessage("Could not sync from tab: " + err.message, "error");
    }
}

// ================= 5. SIGN OUT =================

async function signOutUser() {
    const session = await getValidSession();
    if (session && session.access_token) {
        try {
            await fetch(`${SUPABASE_CONFIG.url}/auth/v1/logout`, {
                method: 'POST',
                headers: {
                    'apikey': SUPABASE_CONFIG.anonKey,
                    'Authorization': `Bearer ${session.access_token}`
                }
            });
        } catch (_) {}
    }
    await chrome.storage.local.remove(['civilmateAuthSession']);
    updateAuthUI(null);

    // Reset dropdowns
    const estSelect = document.getElementById('selectStagedEstimate');
    if (estSelect) estSelect.innerHTML = '<option value="">Sign in to view staged estimates...</option>';
    const billSelect = document.getElementById('selectStagedBill');
    if (billSelect) billSelect.innerHTML = '<option value="">Sign in to view staged bills...</option>';
}

// ================= 6. UI MODAL HELPERS =================

function openAuthModal() {
    const modal = document.getElementById('authModal');
    if (modal) modal.style.display = 'flex';
    clearAuthMessage();
}

function closeAuthModal() {
    const modal = document.getElementById('authModal');
    if (modal) modal.style.display = 'none';
    clearAuthMessage();
}

function showAuthMessage(msg, type) {
    const box = document.getElementById('authMessageBox');
    if (!box) return;
    box.textContent = msg;
    box.style.display = 'block';
    box.className = `auth-msg-box ${type === 'error' ? 'auth-msg-error' : 'auth-msg-success'}`;
}

function clearAuthMessage() {
    const box = document.getElementById('authMessageBox');
    if (box) box.style.display = 'none';
}

function refreshActiveTabExports() {
    if (typeof currentMode !== 'undefined') {
        if (currentMode === 'ESTIMATE_UPLOAD') {
            fetchStagedExportsFromCloud('Estimate', 'selectStagedEstimate', 'btnLoadStagedEstimate');
        } else if (currentMode === 'BILL_UPLOAD') {
            fetchStagedExportsFromCloud('Bill', 'selectStagedBill', 'btnLoadStagedBill');
        }
    }
}

// ================= 7. FETCH OUTBOUND STAGED EXPORTS =================

async function fetchStagedExportsFromCloud(docType, selectElementId, loadBtnId) {
    const select = document.getElementById(selectElementId);
    const loadBtn = document.getElementById(loadBtnId);
    if (!select) return;

    const session = await getValidSession();
    if (!session || !session.user || !session.user.email) {
        select.innerHTML = `<option value="">Sign in to load ${docType.toLowerCase()}s...</option>`;
        if (loadBtn) loadBtn.disabled = true;
        return;
    }

    const email = session.user.email.toLowerCase().trim();
    select.innerHTML = '<option value="">Loading latest packages from cloud...</option>';
    if (loadBtn) loadBtn.disabled = true;

    try {
        const queryUrl = `${SUPABASE_CONFIG.url}/rest/v1/staged_exports?user_email=eq.${encodeURIComponent(email)}&doc_type=eq.${encodeURIComponent(docType)}&order=created_at.desc&limit=20`;
        const res = await fetch(queryUrl, {
            headers: {
                "apikey": SUPABASE_CONFIG.anonKey,
                "Authorization": `Bearer ${session.access_token}`
            }
        });

        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const items = await res.json();

        select.innerHTML = '';
        if (!items || items.length === 0) {
            select.innerHTML = `<option value="">No staged ${docType.toLowerCase()}s found in cloud</option>`;
            if (loadBtn) loadBtn.disabled = true;
            return;
        }

        const defaultOpt = document.createElement('option');
        defaultOpt.value = '';
        defaultOpt.textContent = `-- Select ${docType} (${items.length} available) --`;
        select.appendChild(defaultOpt);

        items.forEach(item => {
            const opt = document.createElement('option');
            opt.value = item.id;
            const dateStr = new Date(item.created_at).toLocaleDateString('en-IN', {
                day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
            });
            opt.textContent = `${item.work_name || 'Untitled'} (${dateStr})`;
            opt.dataset.payload = JSON.stringify(item.details || []);
            select.appendChild(opt);
        });

        select.onchange = () => {
            if (loadBtn) loadBtn.disabled = !select.value;
        };

    } catch (err) {
        console.error("Cloud fetch error:", err);
        select.innerHTML = `<option value="">Cloud busy (Use Paste & Load)</option>`;
        if (loadBtn) loadBtn.disabled = true;
    }
}

// ================= 8. LOAD CLOUD PAYLOAD INTO EXTENSION QUEUE =================

function loadCloudPackageIntoQueue(selectElementId) {
    const select = document.getElementById(selectElementId);
    if (!select || !select.value) return;

    const selectedOpt = select.options[select.selectedIndex];
    if (!selectedOpt || !selectedOpt.dataset.payload) return;

    try {
        const jsonData = JSON.parse(selectedOpt.dataset.payload);
        parseJsonArrayIntoQueue(jsonData);
    } catch (e) {
        alert("Could not load package payload: " + e.message);
    }
}

function parseJsonArrayIntoQueue(jsonData) {
    if (!Array.isArray(jsonData)) {
        throw new Error("Payload must be a JSON array.");
    }

    allItems = [];
    let idCounter = 0;

    jsonData.forEach(group => {
        if (group.items && Array.isArray(group.items)) {
            group.items.forEach(item => {
                const isNS = (item.type === "NS");
                allItems.push({
                    id: idCounter++,
                    main_comp: group.main_comp || "",
                    sub_comp: group.sub_comp || "",
                    type: item.type || "HSR",
                    hsr_no: item.hsr_no || "N/A",
                    rate_type: item.rate_type || "Through Rate",
                    desc: item.desc || (item.child_rows && item.child_rows[0]?.desc) || "Item",
                    total_qty: item.total_qty,
                    data: item,
                    selected: true,
                    status: isNS ? "MANUAL_UPLOAD_REQUIRED" : null,
                    message: isNS ? "NS Item" : null
                });
            });
        } else if (group.hsr_no) {
            allItems.push({
                id: idCounter++,
                main_comp: "",
                sub_comp: "",
                type: group.type || "HSR",
                hsr_no: group.hsr_no || "N/A",
                rate_type: group.rate_type || "Through Rate",
                desc: (group.child_rows && group.child_rows[0]?.desc) || "Item",
                data: group,
                selected: true,
                status: null,
                message: null
            });
        }
    });

    renderList();
    if (elements.btnStart) elements.btnStart.disabled = false;
    if (elements.btnStartBills) elements.btnStartBills.disabled = false;

    // Persist to civilmateState so content script receives it
    chrome.storage.local.set({
        civilmateState: {
            queue: allItems,
            mode: currentMode,
            status: "READY"
        }
    });
}

// ================= 9. INBOUND: STAGE EXTRACTED PDF TO SUPABASE =================

async function stageExtractedPdfToCloud(extractedData) {
    if (!extractedData || extractedData.length === 0) {
        alert("No extracted data available to stage.");
        return;
    }

    const session = await getValidSession();
    if (!session || !session.user || !session.user.email) {
        openAuthModal();
        showAuthMessage("Please sign in to save extracted data to your cloud account.", "error");
        return;
    }

    const stageBtn = document.getElementById('btnStageExtractToCloud');
    if (stageBtn) {
        stageBtn.disabled = true;
        stageBtn.innerHTML = '<span class="material-icons rotating">autorenew</span> Staging to Cloud...';
    }

    const workName = extractedData[0]?.workName || "Extracted PDF";
    const docType = (extractedData[0]?.documentType || '').includes("Estimate") ? "Detailed Estimate" : "BoQ";

    try {
        const res = await fetch(`${SUPABASE_CONFIG.url}/rest/v1/staged_imports`, {
            method: "POST",
            headers: {
                "apikey": SUPABASE_CONFIG.anonKey,
                "Authorization": `Bearer ${session.access_token}`,
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            },
            body: JSON.stringify({
                user_email: session.user.email.toLowerCase().trim(),
                work_name: workName,
                doc_type: docType,
                status: "Ready for Sheets",
                details: extractedData
            })
        });

        if (!res.ok) throw new Error(`HTTP ${res.status}`);

        if (stageBtn) {
            stageBtn.innerHTML = '<span class="material-icons">check</span> Staged to Cloud!';
            stageBtn.style.backgroundColor = 'var(--success)';
            setTimeout(() => {
                stageBtn.disabled = false;
                stageBtn.innerHTML = '<span class="material-icons">cloud_upload</span> Stage to CivilMate Cloud';
            }, 3000);
        }

        alert(`Successfully staged ${extractedData.length} items to CivilMate Cloud!\nOpen your Google Sheets Add-on to import.`);

    } catch (err) {
        console.error("Cloud stage error:", err);
        alert("Could not stage to cloud: " + err.message + "\nYou can still use 'Copy Extracted Data' to paste into Google Sheets.");
        if (stageBtn) {
            stageBtn.disabled = false;
            stageBtn.innerHTML = '<span class="material-icons">cloud_upload</span> Stage to CivilMate Cloud';
        }
    }
}
```

---

### Step 4: Wire Listeners & Event Handlers in `popup.js`

In `document.addEventListener('DOMContentLoaded', async () => { ... })`:

1. **Restore Session on Popup Open**:
   ```javascript
   const session = await getValidSession();
   updateAuthUI(session);
   ```

2. **Auth Event Listeners**:
   ```javascript
   document.getElementById('btnOpenAuthModal')?.addEventListener('click', openAuthModal);
   document.getElementById('btnCloseAuthModal')?.addEventListener('click', closeAuthModal);
   document.getElementById('btnAuthSignOut')?.addEventListener('click', signOutUser);
   
   document.getElementById('btnGoogleSignIn')?.addEventListener('click', signInWithGoogle);
   document.getElementById('btnEmailSignIn')?.addEventListener('click', () => {
       const email = document.getElementById('authInputEmail')?.value;
       const password = document.getElementById('authInputPassword')?.value;
       signInWithEmailPassword(email, password);
   });
   document.getElementById('btnSyncFromPortal')?.addEventListener('click', syncSessionFromPortalTab);
   ```

3. **Staged Package Select & Load Handlers**:
   ```javascript
   document.getElementById('btnLoadStagedEstimate')?.addEventListener('click', () => {
       loadCloudPackageIntoQueue('selectStagedEstimate');
   });
   document.getElementById('btnRefreshStagedEstimates')?.addEventListener('click', () => {
       fetchStagedExportsFromCloud('Estimate', 'selectStagedEstimate', 'btnLoadStagedEstimate');
   });

   document.getElementById('btnLoadStagedBill')?.addEventListener('click', () => {
       loadCloudPackageIntoQueue('selectStagedBill');
   });
   document.getElementById('btnRefreshStagedBills')?.addEventListener('click', () => {
       fetchStagedExportsFromCloud('Bill', 'selectStagedBill', 'btnLoadStagedBill');
   });
   ```

4. **Tab Switch Updates (`switchTab(mode)`)**:
   - When switching to `ESTIMATE_UPLOAD`:
     `fetchStagedExportsFromCloud('Estimate', 'selectStagedEstimate', 'btnLoadStagedEstimate');`
   - When switching to `BILL_UPLOAD`:
     `fetchStagedExportsFromCloud('Bill', 'selectStagedBill', 'btnLoadStagedBill');`

5. **Inbound PDF Staging Handler**:
   - In `startExtraction()`, when extraction finishes (`if (!isExtractStopped)`), enable `#btnStageExtractToCloud`.
   - Wire listener:
     ```javascript
     document.getElementById('btnStageExtractToCloud')?.addEventListener('click', () => {
         stageExtractedPdfToCloud(finalData);
     });
     ```

---

## 6. Offline & Guest Fallback Integrity

The cloud sync and authentication features sit on top of the original extension without breaking offline capability:
- If a user is not signed in or working on an offline workstation without internet access:
  1. The **"Paste & Load"** button (`btnParseClipboard`) continues to read the clipboard and populate `allItems`.
  2. The **"Copy Extracted Data"** button (`btnCopyExtractJson`) continues to copy extracted JSON to clipboard.
- The extension never blocks the engineer from executing uploads or extractions even if Supabase is unreachable.

---

## 7. Verification & Testing Checklist

Before releasing the updated extension:
1. [ ] **Permissions**: Verify `manifest.json` contains `"identity"` under `permissions` and `https://*.supabase.co/*` under `host_permissions`.
2. [ ] **Email/Password Auth**: Sign in with an existing CivilMate email and password. Verify email and avatar appear in the header and session persists when closing and reopening the extension.
3. [ ] **Google OAuth**: Click "Continue with Google". Confirm Google login window opens and returns authenticated session.
4. [ ] **Persistent Session**: Close Chrome completely and reopen. Ensure the extension retains the logged-in user without re-prompting.
5. [ ] **Staged Estimates Tab**: Switch to Estimates tab. Verify dropdown populates with recent estimate exports for that user from `staged_exports`. Click "Load Selected Estimate" and confirm items populate the queue with checkboxes.
6. [ ] **Staged Bills Tab**: Switch to Bills tab. Verify dropdown displays only packages where `doc_type = 'Bill'`.
7. [ ] **PDF Staging**: Extract a BoQ or Detailed Estimate PDF. Click "Stage to CivilMate Cloud". Confirm row is inserted into `public.staged_imports` in Supabase with `status: 'Ready for Sheets'`.
8. [ ] **Sign Out**: Click the logout button. Confirm session is cleared from `chrome.storage.local` and UI switches back to "Guest / Offline Mode".
