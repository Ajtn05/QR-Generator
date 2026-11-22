/**
 * Quick QR — Product Website Interactive Scripts
 * Pure client-side QR generation, vector run-merging, and macOS showcase
 */

(function () {
  'use strict';

  // --- State ---
  const state = {
    payloadKind: 'link',
    correctionLevel: 'M',
    exportFormat: 'svg',
    pngSize: 1024,
    quietZone: 4,
    currentPayload: {
      link: 'https://example.com/menu',
      text: 'Pick up your order at the front desk.',
      wifi: {
        ssid: 'Guest Wi-Fi',
        password: 'example-password',
        security: 'WPA',
        hidden: false
      },
      contact: {
        firstName: 'Alex',
        lastName: 'Morgan',
        organization: '',
        jobTitle: '',
        phone: '+1 415 555 0112',
        email: 'alex@example.com',
        url: 'https://example.com',
        address: ''
      },
      email: {
        to: 'hello@example.com',
        subject: 'Order pickup',
        body: 'When can I pick up my order?'
      },
      sms: {
        number: '+14155550113',
        body: 'I’m at the front desk.'
      },
      phone: {
        number: '+14155550114'
      },
      location: {
        latitude: '37.7749',
        longitude: '-122.4194'
      },
      event: {
        title: 'Open house',
        location: 'Community center',
        notes: '',
        start: '2026-11-25T09:00',
        end: '2026-11-25T11:00',
        allDay: false
      }
    }
  };

  // --- Spec-compliant String Encoding (Mirroring Payload.swift) ---

  function trimmed(s) {
    return (s || '').trim();
  }

  function normalizedURL(raw) {
    const t = trimmed(raw);
    if (!t) return '';
    if (t.includes('://')) return t;
    const lower = t.toLowerCase();
    for (const scheme of ['mailto:', 'tel:', 'sms:', 'geo:', 'wifi:', 'smsto:']) {
      if (lower.startsWith(scheme)) return t;
    }
    return 'https://' + t;
  }

  function wifiEscaped(s) {
    const reserved = new Set(['\\', ';', ',', ':', '"']);
    let out = '';
    for (const ch of s) {
      if (reserved.has(ch)) out += '\\';
      out += ch;
    }
    return out;
  }

  function dialable(s) {
    return (s || '').replace(/[^0-9+]/g, '');
  }

  function vCardEscape(s) {
    return trimmed(s)
      .replace(/\\/g, '\\\\')
      .replace(/;/g, '\\;')
      .replace(/,/g, '\\,')
      .replace(/\n/g, '\\n');
  }

  function formatISODate(dateStr, allDay) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return '';
    if (allDay) {
      const yr = d.getUTCFullYear();
      const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
      const da = String(d.getUTCDate()).padStart(2, '0');
      return `${yr}${mo}${da}`;
    }
    const yr = d.getUTCFullYear();
    const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
    const da = String(d.getUTCDate()).padStart(2, '0');
    const hr = String(d.getUTCHours()).padStart(2, '0');
    const mi = String(d.getUTCMinutes()).padStart(2, '0');
    const se = String(d.getUTCSeconds()).padStart(2, '0');
    return `${yr}${mo}${da}T${hr}${mi}${se}Z`;
  }

  function encodePayload(kind) {
    switch (kind) {
      case 'link':
        return normalizedURL(state.currentPayload.link);

      case 'text':
        return state.currentPayload.text || '';

      case 'wifi': {
        const w = state.currentPayload.wifi;
        const name = trimmed(w.ssid);
        if (!name) return '';
        let out = `WIFI:T:${w.security};S:${wifiEscaped(name)};`;
        if (w.security !== 'nopass' && w.password) {
          out += `P:${wifiEscaped(w.password)};`;
        }
        if (w.hidden) out += 'H:true;';
        return out + ';';
      }

      case 'contact': {
        const c = state.currentPayload.contact;
        const fn = [trimmed(c.firstName), trimmed(c.lastName)].filter(Boolean).join(' ');
        if (!fn && !trimmed(c.organization)) return '';
        const lines = ['BEGIN:VCARD', 'VERSION:3.0'];
        lines.push(`N:${vCardEscape(c.lastName)};${vCardEscape(c.firstName)};;;`);
        lines.push(`FN:${vCardEscape(fn || c.organization)}`);
        if (trimmed(c.organization)) lines.push(`ORG:${vCardEscape(c.organization)}`);
        if (trimmed(c.jobTitle)) lines.push(`TITLE:${vCardEscape(c.jobTitle)}`);
        if (trimmed(c.phone)) lines.push(`TEL;TYPE=CELL:${vCardEscape(c.phone)}`);
        if (trimmed(c.email)) lines.push(`EMAIL;TYPE=INTERNET:${vCardEscape(c.email)}`);
        if (trimmed(c.url)) lines.push(`URL:${vCardEscape(normalizedURL(c.url))}`);
        if (trimmed(c.address)) lines.push(`ADR;TYPE=WORK:;;${vCardEscape(c.address)};;;;`);
        lines.push('END:VCARD');
        return lines.join('\r\n');
      }

      case 'email': {
        const e = state.currentPayload.email;
        const to = trimmed(e.to);
        if (!to) return '';
        const params = [];
        if (trimmed(e.subject)) params.push(`subject=${encodeURIComponent(e.subject)}`);
        if (trimmed(e.body)) params.push(`body=${encodeURIComponent(e.body)}`);
        return params.length ? `mailto:${to}?${params.join('&')}` : `mailto:${to}`;
      }

      case 'sms': {
        const s = state.currentPayload.sms;
        const num = dialable(s.number);
        if (!num) return '';
        const body = trimmed(s.body);
        return body ? `SMSTO:${num}:${body}` : `SMSTO:${num}:`;
      }

      case 'phone': {
        const num = dialable(state.currentPayload.phone.number);
        return num ? `tel:${num}` : '';
      }

      case 'location': {
        const l = state.currentPayload.location;
        const lat = parseFloat(l.latitude);
        const lon = parseFloat(l.longitude);
        if (isNaN(lat) || isNaN(lon)) return '';
        return `geo:${lat},${lon}`;
      }

      case 'event': {
        const ev = state.currentPayload.event;
        const title = trimmed(ev.title);
        if (!title) return '';
        const lines = ['BEGIN:VEVENT', `SUMMARY:${vCardEscape(title)}`];
        const sStamp = formatISODate(ev.start, ev.allDay);
        const eStamp = formatISODate(ev.end, ev.allDay);
        if (ev.allDay) {
          if (sStamp) lines.push(`DTSTART;VALUE=DATE:${sStamp}`);
          if (eStamp) lines.push(`DTEND;VALUE=DATE:${eStamp}`);
        } else {
          if (sStamp) lines.push(`DTSTART:${sStamp}`);
          if (eStamp) lines.push(`DTEND:${eStamp}`);
        }
        if (trimmed(ev.location)) lines.push(`LOCATION:${vCardEscape(ev.location)}`);
        if (trimmed(ev.notes)) lines.push(`DESCRIPTION:${vCardEscape(ev.notes)}`);
        lines.push('END:VEVENT');
        return lines.join('\r\n');
      }

      default:
        return '';
    }
  }

  // --- Slug Generator (Mirroring Filename.swift) ---
  function slug(raw, fallback = 'qrcode') {
    if (!raw) return fallback;
    const sanitized = raw.toLowerCase().replace(/[^a-z0-9_-]/g, '-');
    const clean = sanitized.replace(/-+/g, '-').replace(/^[-_]+|[-_]+$/g, '').slice(0, 48);
    return clean || fallback;
  }

  function getSuggestedName(kind, ext = 'svg') {
    let base = 'qrcode';
    switch (kind) {
      case 'link': {
        const u = normalizedURL(state.currentPayload.link);
        try {
          const host = new URL(u).hostname;
          base = slug(host, 'link');
        } catch (_) {
          base = slug(u, 'link');
        }
        break;
      }
      case 'text':
        base = slug(state.currentPayload.text.slice(0, 32), 'text');
        break;
      case 'wifi':
        base = slug('wifi-' + state.currentPayload.wifi.ssid, 'wifi');
        break;
      case 'contact': {
        const c = state.currentPayload.contact;
        const name = [c.firstName, c.lastName, c.organization].filter(Boolean).join('-');
        base = slug(name, 'contact');
        break;
      }
      case 'email':
        base = slug(state.currentPayload.email.to, 'email');
        break;
      case 'sms':
        base = slug('sms-' + state.currentPayload.sms.number, 'sms');
        break;
      case 'phone':
        base = slug('tel-' + state.currentPayload.phone.number, 'phone');
        break;
      case 'location':
        base = slug(`geo-${state.currentPayload.location.latitude}-${state.currentPayload.location.longitude}`, 'location');
        break;
      case 'event':
        base = slug(state.currentPayload.event.title, 'event');
        break;
    }
    return `${base}.${ext}`;
  }

  // --- Run-Merged SVG Generator (Mirroring QR.swift) ---

  function makeQRMatrix(text, level) {
    if (!text || typeof qrcode === 'undefined') return null;
    try {
      // 0 = auto-version, level = L/M/Q/H
      const qr = qrcode(0, level);
      qr.addData(text);
      qr.make();
      return qr;
    } catch (err) {
      console.warn('QR generation error:', err);
      return null;
    }
  }

  function generateMergedSvgString(qr, quiet) {
    if (!qr) return '';
    const size = qr.getModuleCount();
    const side = size + quiet * 2;
    let d = '';

    for (let y = 0; y < size; y++) {
      let x = 0;
      while (x < size) {
        if (!qr.isDark(y, x)) {
          x++;
          continue;
        }
        let run = 1;
        while (x + run < size && qr.isDark(y, x + run)) {
          run++;
        }
        d += `M${x + quiet} ${y + quiet}h${run}v1h-${run}z`;
        x += run;
      }
    }

    return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${side} ${side}" width="${side * 8}" height="${side * 8}" shape-rendering="crispEdges">
<rect width="${side}" height="${side}" fill="#ffffff"/>
<path fill="#000000" d="${d}"/>
</svg>`;
  }

  // Probe headroom before next version change (mirroring QR.headroom in Swift)
  function probeHeadroom(text, level, currentVersion) {
    if (!text || !currentVersion) return null;
    const filler = 'x';

    function sameVersion(extra) {
      try {
        const probeQr = qrcode(0, level);
        probeQr.addData(text + filler.repeat(extra));
        probeQr.make();
        const v = (probeQr.getModuleCount() - 17) / 4;
        return v === currentVersion;
      } catch (_) {
        return false;
      }
    }

    let fits = 0;
    let over = 1;
    while (over <= 512 && sameVersion(over)) {
      fits = over;
      over *= 2;
    }
    if (over > 512) return fits;
    while (fits + 1 < over) {
      const mid = Math.floor((fits + over) / 2);
      if (sameVersion(mid)) fits = mid;
      else over = mid;
    }
    return fits;
  }

  // --- DOM Elements ---
  const formFieldsContainer = document.getElementById('formFieldsContainer');
  const payloadTypeList = document.getElementById('payloadTypeList');
  const qrSvgContainer = document.getElementById('qrSvgContainer');
  const inspectorDetails = document.getElementById('inspectorDetails');
  const encodedPayloadText = document.getElementById('encodedPayloadText');
  const quietZoneSlider = document.getElementById('quietZoneSlider');
  const quietZoneDisplay = document.getElementById('quietZoneDisplay');
  const quietZoneHint = document.getElementById('quietZoneHint');
  const correctionSelect = document.getElementById('correctionSelect');
  const formatSelector = document.getElementById('formatSelector');
  const pngSizeGroup = document.getElementById('pngSizeGroup');
  const pngSizeSelect = document.getElementById('pngSizeSelect');
  const btnDownload = document.getElementById('btnDownload');
  const btnCopy = document.getElementById('btnCopy');
  const actionStatus = document.getElementById('actionStatus');

  function escapeHtml(value) {
    return value.replace(/[&<>"']/g, (character) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    })[character]);
  }

  // --- Render Dynamic Form ---
  function renderFormFields() {
    if (!formFieldsContainer) return;
    const kind = state.payloadKind;
    let html = '';

    switch (kind) {
      case 'link':
        html = `
          <div class="form-group">
            <label for="inputLink">Link URL</label>
            <input type="text" id="inputLink" class="form-input" value="${escapeHtml(state.currentPayload.link)}" placeholder="example.com">
            <span class="form-hint">Without a scheme it's saved as https://</span>
          </div>`;
        break;

      case 'text':
        html = `
          <div class="form-group">
            <label for="inputText">Plain Text</label>
            <textarea id="inputText" class="form-textarea" rows="4" placeholder="Anything at all">${escapeHtml(state.currentPayload.text)}</textarea>
          </div>`;
        break;

      case 'wifi':
        html = `
          <div class="form-group">
            <label for="inputWifiSsid">Network Name (SSID)</label>
            <input type="text" id="inputWifiSsid" class="form-input" value="${escapeHtml(state.currentPayload.wifi.ssid)}" placeholder="MyOffice-WiFi">
          </div>
          <div class="form-row-2">
            <div class="form-group">
              <label for="inputWifiSecurity">Security</label>
              <select id="inputWifiSecurity" class="form-select">
                <option value="WPA" ${state.currentPayload.wifi.security === 'WPA' ? 'selected' : ''}>WPA/WPA2/WPA3</option>
                <option value="WEP" ${state.currentPayload.wifi.security === 'WEP' ? 'selected' : ''}>WEP</option>
                <option value="nopass" ${state.currentPayload.wifi.security === 'nopass' ? 'selected' : ''}>Open (None)</option>
              </select>
            </div>
            <div class="form-group" id="wifiPassGroup" style="${state.currentPayload.wifi.security === 'nopass' ? 'display:none;' : ''}">
              <label for="inputWifiPassword">Password</label>
              <input type="password" id="inputWifiPassword" class="form-input" value="${escapeHtml(state.currentPayload.wifi.password)}" placeholder="Network password">
            </div>
          </div>
          <div class="form-group">
            <label class="form-checkbox-label">
              <input type="checkbox" id="inputWifiHidden" ${state.currentPayload.wifi.hidden ? 'checked' : ''}>
              <span>Hidden network</span>
            </label>
            <span class="form-hint">Scanning joins the network directly on iOS and Android.</span>
          </div>`;
        break;

      case 'contact':
        html = `
          <div class="form-row-2">
            <div class="form-group">
              <label for="inputContactFirst">First Name</label>
              <input type="text" id="inputContactFirst" class="form-input" value="${escapeHtml(state.currentPayload.contact.firstName)}">
            </div>
            <div class="form-group">
              <label for="inputContactLast">Last Name</label>
              <input type="text" id="inputContactLast" class="form-input" value="${escapeHtml(state.currentPayload.contact.lastName)}">
            </div>
          </div>
          <div class="form-row-2">
            <div class="form-group">
              <label for="inputContactOrg">Organization</label>
              <input type="text" id="inputContactOrg" class="form-input" value="${escapeHtml(state.currentPayload.contact.organization)}">
            </div>
            <div class="form-group">
              <label for="inputContactTitle">Job Title</label>
              <input type="text" id="inputContactTitle" class="form-input" value="${escapeHtml(state.currentPayload.contact.jobTitle)}">
            </div>
          </div>
          <div class="form-row-2">
            <div class="form-group">
              <label for="inputContactPhone">Phone Number</label>
              <input type="text" id="inputContactPhone" class="form-input" value="${escapeHtml(state.currentPayload.contact.phone)}">
            </div>
            <div class="form-group">
              <label for="inputContactEmail">Email</label>
              <input type="email" id="inputContactEmail" class="form-input" value="${escapeHtml(state.currentPayload.contact.email)}">
            </div>
          </div>
          <div class="form-group">
            <label for="inputContactUrl">Website</label>
            <input type="text" id="inputContactUrl" class="form-input" value="${escapeHtml(state.currentPayload.contact.url)}">
          </div>
          <div class="form-group">
            <label for="inputContactAddress">Address</label>
            <textarea id="inputContactAddress" class="form-textarea" rows="2">${escapeHtml(state.currentPayload.contact.address)}</textarea>
          </div>`;
        break;

      case 'email':
        html = `
          <div class="form-group">
            <label for="inputEmailTo">Recipient Email</label>
            <input type="email" id="inputEmailTo" class="form-input" value="${escapeHtml(state.currentPayload.email.to)}">
          </div>
          <div class="form-group">
            <label for="inputEmailSubject">Subject</label>
            <input type="text" id="inputEmailSubject" class="form-input" value="${escapeHtml(state.currentPayload.email.subject)}">
          </div>
          <div class="form-group">
            <label for="inputEmailBody">Message Body</label>
            <textarea id="inputEmailBody" class="form-textarea" rows="3">${escapeHtml(state.currentPayload.email.body)}</textarea>
          </div>`;
        break;

      case 'sms':
        html = `
          <div class="form-group">
            <label for="inputSmsNumber">Phone Number</label>
            <input type="text" id="inputSmsNumber" class="form-input" value="${escapeHtml(state.currentPayload.sms.number)}">
          </div>
          <div class="form-group">
            <label for="inputSmsBody">Message</label>
            <textarea id="inputSmsBody" class="form-textarea" rows="3">${escapeHtml(state.currentPayload.sms.body)}</textarea>
          </div>`;
        break;

      case 'phone':
        html = `
          <div class="form-group">
            <label for="inputPhoneNumber">Phone Number</label>
            <input type="tel" id="inputPhoneNumber" class="form-input" value="${escapeHtml(state.currentPayload.phone.number)}">
          </div>`;
        break;

      case 'location':
        html = `
          <div class="form-row-2">
            <div class="form-group">
              <label for="inputGeoLat">Latitude</label>
              <input type="text" id="inputGeoLat" class="form-input" value="${escapeHtml(state.currentPayload.location.latitude)}">
            </div>
            <div class="form-group">
              <label for="inputGeoLon">Longitude</label>
              <input type="text" id="inputGeoLon" class="form-input" value="${escapeHtml(state.currentPayload.location.longitude)}">
            </div>
          </div>
          <span class="form-hint">Decimal degrees. Opens in Apple Maps and Google Maps.</span>`;
        break;

      case 'event':
        html = `
          <div class="form-group">
            <label for="inputEventTitle">Event Title</label>
            <input type="text" id="inputEventTitle" class="form-input" value="${escapeHtml(state.currentPayload.event.title)}">
          </div>
          <div class="form-group">
            <label for="inputEventLocation">Location</label>
            <input type="text" id="inputEventLocation" class="form-input" value="${escapeHtml(state.currentPayload.event.location)}">
          </div>
          <div class="form-row-2">
            <div class="form-group">
              <label for="inputEventStart">Starts</label>
              <input type="datetime-local" id="inputEventStart" class="form-input" value="${escapeHtml(state.currentPayload.event.start)}">
            </div>
            <div class="form-group">
              <label for="inputEventEnd">Ends</label>
              <input type="datetime-local" id="inputEventEnd" class="form-input" value="${escapeHtml(state.currentPayload.event.end)}">
            </div>
          </div>
          <div class="form-group">
            <label for="inputEventNotes">Notes</label>
            <textarea id="inputEventNotes" class="form-textarea" rows="2">${escapeHtml(state.currentPayload.event.notes)}</textarea>
          </div>`;
        break;
    }

    formFieldsContainer.innerHTML = html;
    bindFormEvents();
  }

  function bindFormEvents() {
    const kind = state.payloadKind;
    switch (kind) {
      case 'link': {
        const inp = document.getElementById('inputLink');
        if (inp) inp.addEventListener('input', (e) => {
          state.currentPayload.link = e.target.value;
          updateStudio();
        });
        break;
      }
      case 'text': {
        const inp = document.getElementById('inputText');
        if (inp) inp.addEventListener('input', (e) => {
          state.currentPayload.text = e.target.value;
          updateStudio();
        });
        break;
      }
      case 'wifi': {
        const s = document.getElementById('inputWifiSsid');
        const p = document.getElementById('inputWifiPassword');
        const sec = document.getElementById('inputWifiSecurity');
        const hid = document.getElementById('inputWifiHidden');
        if (s) s.addEventListener('input', (e) => { state.currentPayload.wifi.ssid = e.target.value; updateStudio(); });
        if (p) p.addEventListener('input', (e) => { state.currentPayload.wifi.password = e.target.value; updateStudio(); });
        if (sec) sec.addEventListener('change', (e) => {
          state.currentPayload.wifi.security = e.target.value;
          const passGroup = document.getElementById('wifiPassGroup');
          if (passGroup) passGroup.style.display = e.target.value === 'nopass' ? 'none' : '';
          updateStudio();
        });
        if (hid) hid.addEventListener('change', (e) => { state.currentPayload.wifi.hidden = e.target.checked; updateStudio(); });
        break;
      }
      case 'contact': {
        ['First', 'Last', 'Org', 'Title', 'Phone', 'Email', 'Url', 'Address'].forEach((field) => {
          const el = document.getElementById('inputContact' + field);
          const keyMap = {
            First: 'firstName', Last: 'lastName', Org: 'organization', Title: 'jobTitle',
            Phone: 'phone', Email: 'email', Url: 'url', Address: 'address'
          };
          if (el) el.addEventListener('input', (e) => {
            state.currentPayload.contact[keyMap[field]] = e.target.value;
            updateStudio();
          });
        });
        break;
      }
      case 'email': {
        ['To', 'Subject', 'Body'].forEach((f) => {
          const el = document.getElementById('inputEmail' + f);
          const k = f.toLowerCase();
          if (el) el.addEventListener('input', (e) => { state.currentPayload.email[k] = e.target.value; updateStudio(); });
        });
        break;
      }
      case 'sms': {
        const n = document.getElementById('inputSmsNumber');
        const b = document.getElementById('inputSmsBody');
        if (n) n.addEventListener('input', (e) => { state.currentPayload.sms.number = e.target.value; updateStudio(); });
        if (b) b.addEventListener('input', (e) => { state.currentPayload.sms.body = e.target.value; updateStudio(); });
        break;
      }
      case 'phone': {
        const p = document.getElementById('inputPhoneNumber');
        if (p) p.addEventListener('input', (e) => { state.currentPayload.phone.number = e.target.value; updateStudio(); });
        break;
      }
      case 'location': {
        const lat = document.getElementById('inputGeoLat');
        const lon = document.getElementById('inputGeoLon');
        if (lat) lat.addEventListener('input', (e) => { state.currentPayload.location.latitude = e.target.value; updateStudio(); });
        if (lon) lon.addEventListener('input', (e) => { state.currentPayload.location.longitude = e.target.value; updateStudio(); });
        break;
      }
      case 'event': {
        ['Title', 'Location', 'Start', 'End', 'Notes'].forEach((f) => {
          const el = document.getElementById('inputEvent' + f);
          const k = f.toLowerCase();
          if (el) el.addEventListener('input', (e) => { state.currentPayload.event[k] = e.target.value; updateStudio(); });
        });
        break;
      }
    }
  }

  // --- Update Studio View ---
  let cachedSvg = '';
  let cachedQr = null;

  function updateStudio() {
    const encoded = encodePayload(state.payloadKind);
    if (encodedPayloadText) {
      encodedPayloadText.textContent = encoded || '(Nothing encoded yet)';
    }

    const qr = makeQRMatrix(encoded, state.correctionLevel);
    cachedQr = qr;
    btnDownload.disabled = !qr;
    btnCopy.disabled = !qr;

    if (!qr) {
      const message = encoded ? 'Shorten the content to make a QR code.' : 'Enter content to make a QR code.';
      const notice = document.createElement('span');
      notice.textContent = message;
      notice.toggleAttribute('data-error', Boolean(encoded));
      qrSvgContainer.replaceChildren(notice);
      inspectorDetails.textContent = 'No code to inspect.';
      cachedSvg = '';
      actionStatus.textContent = '';
      return;
    }

    const size = qr.getModuleCount();
    const version = (size - 17) / 4;
    const quiet = state.quietZone;
    const totalModules = size * size;
    let darkCount = 0;

    for (let r = 0; r < size; r++) {
      for (let c = 0; c < size; c++) {
        if (qr.isDark(r, c)) darkCount++;
      }
    }

    const density = ((darkCount / totalModules) * 100).toFixed(1);
    const side = size + quiet * 2;
    const recoveryMap = { L: 7, M: 15, Q: 25, H: 30 };
    const recovery = recoveryMap[state.correctionLevel] || 15;

    // Probe how many ASCII bytes fit before the symbol grows.
    const headroom = probeHeadroom(encoded, state.correctionLevel, version);

    // Generate merged SVG
    cachedSvg = generateMergedSvgString(qr, quiet);
    if (qrSvgContainer) {
      qrSvgContainer.innerHTML = cachedSvg;
    }

    // Inspector Rows
    const utf8Bytes = new TextEncoder().encode(encoded).length;
    let detailsHtml = `
      <div class="inspector-row">
        <span class="label">Version</span>
        <span class="value">v${version} · ${size}×${size}</span>
      </div>
      <div class="inspector-row">
        <span class="label">Correction</span>
        <span class="value">Level ${state.correctionLevel} · ${recovery}% recovery</span>
      </div>
      <div class="inspector-row">
        <span class="label">Payload</span>
        <span class="value">${utf8Bytes} bytes</span>
      </div>
    `;

    if (headroom !== null) {
      const roomText = headroom === 0 ? `full at v${version}` : `+${headroom} bytes before v${version + 1}`;
      detailsHtml += `
        <div class="inspector-row">
          <span class="label">Headroom</span>
          <span class="value">${roomText}</span>
        </div>`;
    }

    detailsHtml += `
      <div class="inspector-row">
        <span class="label">Dark modules</span>
        <span class="value">${darkCount}/${totalModules} · ${density}%</span>
      </div>
    `;

    if (state.exportFormat === 'svg') {
      detailsHtml += `
        <div class="inspector-row">
          <span class="label">Quiet zone</span>
          <span class="value">${quiet} of ${side} modules</span>
        </div>
        <div class="inspector-row">
          <span class="label">Output</span>
          <span class="value">${side}-module viewBox · vector</span>
        </div>`;
    } else {
      const targetPx = parseInt(state.pngSize, 10) || 1024;
      const scale = Math.floor(targetPx / side) || 1;
      const resolvedPx = side * scale;
      detailsHtml += `
        <div class="inspector-row">
          <span class="label">Quiet zone</span>
          <span class="value">${quiet} mod · ${quiet * scale} px</span>
        </div>
        <div class="inspector-row">
          <span class="label">Output</span>
          <span class="value">${resolvedPx} × ${resolvedPx} px</span>
        </div>
        <div class="inspector-row">
          <span class="label">Scale</span>
          <span class="value">${scale} px/module</span>
        </div>`;
    }

    if (inspectorDetails) {
      inspectorDetails.innerHTML = detailsHtml;
    }

    if (actionStatus) {
      actionStatus.textContent = '';
    }
  }

  // --- Downloads and Clipboard Copy ---

  function downloadFile(content, fileName, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }, 150);
  }

  function downloadCanvasAsPng(qr, quiet, targetPx, fileName) {
    if (!qr) return;
    const size = qr.getModuleCount();
    const side = size + quiet * 2;
    const scale = Math.max(1, Math.floor(targetPx / side));
    const pixels = side * scale;

    const canvas = document.createElement('canvas');
    canvas.width = pixels;
    canvas.height = pixels;
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingEnabled = false;

    // Fill white background
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, pixels, pixels);

    // Fill dark modules
    ctx.fillStyle = '#000000';
    for (let y = 0; y < size; y++) {
      let x = 0;
      while (x < size) {
        if (!qr.isDark(y, x)) { x++; continue; }
        let run = 1;
        while (x + run < size && qr.isDark(y, x + run)) { run++; }
        ctx.fillRect((x + quiet) * scale, (y + quiet) * scale, run * scale, scale);
        x += run;
      }
    }

    canvas.toBlob((blob) => {
      if (!blob) return;
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      document.body.appendChild(a);
      a.click();
      setTimeout(() => {
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
      }, 150);
    }, 'image/png');
  }

  function handleDownload() {
    if (!cachedQr) return;
    const ext = state.exportFormat === 'svg' ? 'svg' : 'png';
    const fileName = getSuggestedName(state.payloadKind, ext);

    if (state.exportFormat === 'svg') {
      downloadFile(cachedSvg, fileName, 'image/svg+xml');
      if (actionStatus) actionStatus.textContent = `Downloaded ${fileName}`;
    } else {
      const targetPx = parseInt(state.pngSize, 10) || 1024;
      downloadCanvasAsPng(cachedQr, state.quietZone, targetPx, fileName);
      if (actionStatus) actionStatus.textContent = `Downloaded ${fileName}`;
    }
  }

  async function handleCopy() {
    if (!cachedQr) return;
    if (state.exportFormat === 'svg') {
      try {
        await navigator.clipboard.writeText(cachedSvg);
        if (actionStatus) actionStatus.textContent = 'Copied SVG source to clipboard';
      } catch (err) {
        if (actionStatus) actionStatus.textContent = 'Copy failed: ' + err.message;
      }
    } else {
      const size = cachedQr.getModuleCount();
      const quiet = state.quietZone;
      const side = size + quiet * 2;
      const targetPx = parseInt(state.pngSize, 10) || 1024;
      const scale = Math.max(1, Math.floor(targetPx / side));
      const pixels = side * scale;

      const canvas = document.createElement('canvas');
      canvas.width = pixels;
      canvas.height = pixels;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, pixels, pixels);
      ctx.fillStyle = '#000000';

      for (let y = 0; y < size; y++) {
        let x = 0;
        while (x < size) {
          if (!cachedQr.isDark(y, x)) { x++; continue; }
          let run = 1;
          while (x + run < size && cachedQr.isDark(y, x + run)) { run++; }
          ctx.fillRect((x + quiet) * scale, (y + quiet) * scale, run * scale, scale);
          x += run;
        }
      }

      canvas.toBlob(async (blob) => {
        if (!blob) return;
        try {
          await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
          if (actionStatus) actionStatus.textContent = 'Copied PNG image to clipboard';
        } catch (_) {
          // Fallback to text copy or status
          if (actionStatus) actionStatus.textContent = 'Clipboard write image not permitted in browser';
        }
      }, 'image/png');
    }
  }

  // --- Seam Comparison Interactive Visualizer ---
  function initSeamVisualizer() {
    const btnMerged = document.getElementById('btnShowMerged');
    const btnNaive = document.getElementById('btnShowNaive');
    const comparisonStatus = document.getElementById('comparisonStatus');
    const demoGraphicMerged = document.getElementById('demoGraphicMerged');

    if (!demoGraphicMerged) return;

    // We draw a 7x7 finder pattern module corner (zoomed in, 140x140 area)
    // Module grid size: 20px per module
    // Finder pattern rows:
    // row 0: 7 dark
    // row 1: dark, 5 white, dark
    // row 2: dark, white, 3 dark, white, dark
    // row 3: dark, white, 3 dark, white, dark
    // row 4: dark, white, 3 dark, white, dark
    // row 5: dark, 5 white, dark
    // row 6: 7 dark

    function renderComparisonGraphic(isMerged) {
      let markup = '';
      const m = 20; // 20px per module

      if (isMerged) {
        // Run-merged continuous paths
        // Row 0: M 0 0 h 140 v 20 h -140 Z
        markup += `<rect width="140" height="140" fill="#ffffff" rx="4"/>`;
        markup += `<g fill="#0b0c10">
          <path d="
            M 0 0 h 140 v 20 h -140 Z
            M 0 20 h 20 v 20 h -20 Z M 120 20 h 20 v 20 h -20 Z
            M 0 40 h 20 v 20 h -20 Z M 40 40 h 60 v 20 h -60 Z M 120 40 h 20 v 20 h -20 Z
            M 0 60 h 20 v 20 h -20 Z M 40 60 h 60 v 20 h -60 Z M 120 60 h 20 v 20 h -20 Z
            M 0 80 h 20 v 20 h -20 Z M 40 80 h 60 v 20 h -60 Z M 120 80 h 20 v 20 h -20 Z
            M 0 100 h 20 v 20 h -20 Z M 120 100 h 20 v 20 h -20 Z
            M 0 120 h 140 v 20 h -140 Z
          "/>
        </g>`;
      } else {
        // Naive 1x1 rectangles with visible hairline anti-aliasing gaps
        markup += `<rect width="140" height="140" fill="#ffffff" rx="4"/>`;
        markup += `<g fill="#0b0c10" stroke="#f43f5e" stroke-width="0.8" stroke-dasharray="2,2">`;
        // Top bar: 7 individual squares with hairline gap representation
        for (let x = 0; x < 7; x++) {
          markup += `<rect x="${x * m}" y="0" width="${m}" height="${m}"/>`;
        }
        // Middle rows
        markup += `<rect x="0" y="20" width="${m}" height="${m}"/>`;
        markup += `<rect x="120" y="20" width="${m}" height="${m}"/>`;

        for (let y = 2; y <= 4; y++) {
          markup += `<rect x="0" y="${y * m}" width="${m}" height="${m}"/>`;
          for (let x = 2; x <= 4; x++) {
            markup += `<rect x="${x * m}" y="${y * m}" width="${m}" height="${m}"/>`;
          }
          markup += `<rect x="120" y="${y * m}" width="${m}" height="${m}"/>`;
        }

        markup += `<rect x="0" y="100" width="${m}" height="${m}"/>`;
        markup += `<rect x="120" y="100" width="${m}" height="${m}"/>`;

        for (let x = 0; x < 7; x++) {
          markup += `<rect x="${x * m}" y="120" width="${m}" height="${m}"/>`;
        }
        markup += `</g>`;

      }

      demoGraphicMerged.innerHTML = markup;
    }

    if (btnMerged && btnNaive) {
      btnMerged.addEventListener('click', () => {
        btnMerged.classList.add('active');
        btnNaive.classList.remove('active');
        btnMerged.setAttribute('aria-pressed', 'true');
        btnNaive.setAttribute('aria-pressed', 'false');
        comparisonStatus.textContent = 'Joined rows have fewer edges between neighboring dark squares.';
        renderComparisonGraphic(true);
      });

      btnNaive.addEventListener('click', () => {
        btnNaive.classList.add('active');
        btnMerged.classList.remove('active');
        btnMerged.setAttribute('aria-pressed', 'false');
        btnNaive.setAttribute('aria-pressed', 'true');
        comparisonStatus.textContent = 'The dashed lines show where individual squares meet. Thin seams can appear along these edges when the image is scaled.';
        renderComparisonGraphic(false);
      });
    }

    renderComparisonGraphic(true);
  }

  // --- Showcase Tabs (Switch App Screenshots) ---
  function initShowcaseTabs() {
    const tabs = document.querySelectorAll('.showcase-tab');
    const containers = {
      link: document.getElementById('view-link'),
      light: document.getElementById('view-light'),
      wifi: document.getElementById('view-wifi'),
      contact: document.getElementById('view-contact'),
      batch: document.getElementById('view-batch')
    };

    tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        const target = tab.getAttribute('data-target');
        tabs.forEach((t) => {
          t.classList.remove('active');
          t.setAttribute('aria-pressed', 'false');
        });
        tab.classList.add('active');
        tab.setAttribute('aria-pressed', 'true');

        Object.keys(containers).forEach((k) => {
          if (containers[k]) containers[k].classList.remove('active');
        });

        if (containers[target]) {
          containers[target].classList.add('active');
        }

      });
    });
  }

  // --- Batch Export Simulator ---
  function initBatchSimulator() {
    const batchInputText = document.getElementById('batchInputText');
    const btnRunBatch = document.getElementById('btnRunBatchSimulation');
    const batchSimResults = document.getElementById('batchSimResults');
    const simFileList = document.getElementById('simFileList');
    const batchCountBadge = document.getElementById('batchCountBadge');

    function updateCount() {
      if (!batchInputText || !batchCountBadge) return;
      const lines = batchInputText.value
        .split('\n')
        .map((l) => l.trim())
        .filter(Boolean);
      batchCountBadge.textContent = `${lines.length} entr${lines.length === 1 ? 'y' : 'ies'}`;
    }

    if (batchInputText) {
      batchInputText.addEventListener('input', updateCount);
    }

    if (btnRunBatch && batchInputText && batchSimResults && simFileList) {
      btnRunBatch.addEventListener('click', () => {
        const lines = batchInputText.value
          .split('\n')
          .map((l) => l.trim())
          .filter(Boolean);

        if (lines.length === 0) {
          batchSimResults.style.display = 'none';
          return;
        }

        const used = new Set();
        const items = lines.map((line) => {
          let host;
          try {
            host = new URL(normalizedURL(line)).hostname;
          } catch (_) {
            // Use the original entry when it doesn't have a hostname.
          }

          const base = slug((host || line).slice(0, 48));
          let name = base;
          for (let suffix = 2; used.has(name); suffix++) {
            name = `${base}-${suffix}`;
          }
          used.add(name);

          const item = document.createElement('div');
          item.className = 'sim-file-item';
          const filename = document.createElement('span');
          filename.className = 'sim-file-name';
          filename.textContent = `${name}.svg`;
          const original = document.createElement('span');
          original.className = 'sim-file-tag';
          original.textContent = line;
          item.append(filename, original);
          return item;
        });

        simFileList.replaceChildren(...items);
        batchSimResults.style.display = 'block';
      });
    }
  }

  // --- Theme Toggle ---
  function initTheme() {
    const themeToggle = document.getElementById('themeToggle');
    const systemTheme = matchMedia('(prefers-color-scheme: dark)');
    let preference = localStorage.getItem('quickqr_theme');

    function updateTheme() {
      const dark = preference ? preference === 'dark' : systemTheme.matches;
      document.body.classList.toggle('theme-dark', dark);
      document.body.classList.toggle('theme-light', !dark);
      const label = dark ? 'Switch to light mode' : 'Switch to dark mode';
      themeToggle.setAttribute('aria-label', label);
      themeToggle.title = label;
    }

    themeToggle.addEventListener('click', () => {
      preference = document.body.classList.contains('theme-dark') ? 'light' : 'dark';
      localStorage.setItem('quickqr_theme', preference);
      updateTheme();
    });
    systemTheme.addEventListener('change', updateTheme);
    updateTheme();
  }

  // --- CLI Copy Button ---
  function initCliCopy() {
    const btn = document.getElementById('cliCopyBtn');
    if (!btn) return;
    btn.addEventListener('click', async () => {
      const cmd = btn.parentElement.querySelector('code').textContent;
      try {
        await navigator.clipboard.writeText(cmd);
        const textSpan = btn.querySelector('.copy-text');
        if (textSpan) {
          textSpan.textContent = 'Copied';
          setTimeout(() => { textSpan.textContent = 'Copy'; }, 2000);
        }
      } catch (err) {
        console.error('Clipboard copy error:', err);
      }
    });
  }

  // --- Event Bindings for Controls ---
  function initControls() {
    // Payload type clicks
    if (payloadTypeList) {
      payloadTypeList.addEventListener('click', (e) => {
        const button = e.target.closest('.type-item');
        if (!button) return;
        const type = button.dataset.type;
        if (!type || type === state.payloadKind) return;

        payloadTypeList.querySelectorAll('.type-item').forEach((item) => {
          item.classList.toggle('active', item === button);
          item.setAttribute('aria-pressed', String(item === button));
        });
        state.payloadKind = type;
        renderFormFields();
        updateStudio();
      });
    }

    // Quiet zone slider
    if (quietZoneSlider && quietZoneDisplay && quietZoneHint) {
      quietZoneSlider.addEventListener('input', (e) => {
        const val = parseInt(e.target.value, 10);
        state.quietZone = val;
        quietZoneDisplay.textContent = `${val} mod`;

        if (val < 4) {
          quietZoneHint.textContent = 'Below the ISO 18004 minimum of 4 modules.';
          quietZoneHint.classList.add('warning');
        } else {
          quietZoneHint.textContent = 'ISO 18004 specifies 4 modules as the minimum.';
          quietZoneHint.classList.remove('warning');
        }
        updateStudio();
      });
    }

    // Correction level select
    if (correctionSelect) {
      correctionSelect.addEventListener('change', (e) => {
        state.correctionLevel = e.target.value;
        updateStudio();
      });
    }

    // Format segmented buttons
    if (formatSelector) {
      formatSelector.addEventListener('click', (e) => {
        const btn = e.target.closest('.seg-btn');
        if (!btn) return;
        const fmt = btn.getAttribute('data-format');
        if (!fmt) return;

        formatSelector.querySelectorAll('.seg-btn').forEach((item) => {
          item.classList.toggle('active', item === btn);
          item.setAttribute('aria-pressed', String(item === btn));
        });
        state.exportFormat = fmt;

        if (pngSizeGroup) {
          pngSizeGroup.style.display = fmt === 'png' ? 'flex' : 'none';
        }
        updateStudio();
      });
    }

    // PNG Size select
    if (pngSizeSelect) {
      pngSizeSelect.addEventListener('change', (e) => {
        state.pngSize = parseInt(e.target.value, 10) || 1024;
        updateStudio();
      });
    }

    // Download & Copy buttons
    if (btnDownload) btnDownload.addEventListener('click', handleDownload);
    if (btnCopy) btnCopy.addEventListener('click', handleCopy);
  }

  // --- Bootstrap ---
  document.addEventListener('DOMContentLoaded', () => {
    if (typeof qrcode !== 'undefined') {
      const utf8 = new TextEncoder();
      qrcode.stringToBytes = (value) => utf8.encode(value);
    }
    initTheme();
    initShowcaseTabs();
    initSeamVisualizer();
    renderFormFields();
    initControls();
    updateStudio();
    initBatchSimulator();
    initCliCopy();
  });
})();
