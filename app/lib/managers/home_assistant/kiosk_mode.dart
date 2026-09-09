/// HA kiosk mode: hide the Home Assistant header and/or sidebar, per the
/// user's choice (some people rely on the header tabs to move between
/// views, so neither is mandatory).
///
/// This used to be able to defer to the kiosk-mode HACS resource, driving it
/// through `?kiosk` URL parameters. That is gone: the resource opens a
/// websocket subscription to every state change in the instance and sorts
/// them out in the browser, which is a heavy enough stream on a wall tablet
/// that Home Assistant disconnects it for falling behind, and the app cannot
/// filter what it never sees. Hiding a header is not worth a connection, so
/// the app does the hiding itself.
///
/// Doing it ourselves means reaching into Home Assistant's shadow DOM, which
/// is private and moves between releases. The approach is chosen to age as
/// well as that allows:
///
///  - Elements are found by custom-element tag name (`ha-drawer`, `hui-root`)
///    rather than by tree position. Tag names are the most stable thing about
///    the frontend; the shape around them is not.
///  - Every shadow root is caught as it is created, by wrapping
///    `attachShadow` before the frontend runs. No polling, no waiting for a
///    tree to settle, and panels mounted an hour later are styled the moment
///    they exist.
///  - The styles name several generations of each element at once (the mwc
///    drawer's `.mdc-drawer` and the current `.sidebar-shell`, `app-header`
///    and `ch-header`), so a release that moves to the next one is already
///    covered and an obsolete selector just matches nothing.
///
/// A hidden sidebar also stays hidden: the edge swipe and the menu button
/// both work by opening the drawer, so the toggle event is swallowed and the
/// drawer's `open` attribute is stripped if anything sets it anyway.
library;

import 'dart:convert';

/// Document-start script. Always injected, and acts only while its flags say
/// so, so the setting applies live with no page reload (the same contract the
/// pull-to-refresh and carousel scripts use). [kioskModeApplyJs] drives it.
const kioskModeScript = '''
(function () {
  if (window.__ksKiosk) return;
  var ID = 'ks-kiosk-mode';
  var S = { on: false, header: true, sidebar: true };
  var ROOTS = [document];
  var ROOT_SEEN = [];
  window.__ksKiosk = S;

  // Outside the dashboard's own WebView the script is handed the one origin
  // it may touch, so a page that navigates on from Home Assistant to
  // somewhere else keeps its own header and sidebar. The dashboard sets no
  // list: everything it loads is the dashboard.
  function allowedHere() {
    var o = window.__ksKioskOrigins;
    return !o || !o.length || o.indexOf(location.origin) >= 0;
  }

  function css() {
    if (!S.on || !allowedHere()) return '';
    var out = '';
    if (S.header) {
      // Header variants across HA frontend generations.
      out += 'app-header,ch-header,ha-top-app-bar-fixed,hui-top-app-bar-fixed,' +
        'hui-view-header,.header,.toolbar{display:none!important;max-height:0!important;min-height:0!important;}';
      // Keep panel cards full-height when the header is gone.
      out += '#view,hui-view,.view{padding-top:calc(var(--safe-area-inset-top,0px) + ' +
        'var(--view-container-padding-top,0px))!important;min-height:100vh!important;' +
        '--kiosk-header-height:0px!important;}';
    }
    if (S.sidebar) {
      // Sidebar/drawer variants across HA frontend generations.
      out += 'ha-sidebar,.mdc-drawer,.sidebar,.sidebar-shell,[slot="drawer"],[part="drawer"]{' +
        'display:none!important;width:0!important;min-width:0!important;max-width:0!important;border:0!important;}';
      // Newer HA and custom-sidebar hosts seen in the field.
      out += 'ha-navigation-sidebar,ha-sidebar-navigation,ha-drawer-sidebar{' +
        'display:none!important;width:0!important;min-width:0!important;max-width:0!important;border:0!important;}';
      out += '.mdc-drawer-scrim{display:none!important;}';
      out += '.mdc-drawer-app-content,.app-content,main{margin-left:0!important;margin-inline-start:0!important;' +
        'padding-left:0!important;padding-inline-start:0!important;}';
      out += 'home-assistant-main{margin-left:0!important;margin-inline-start:0!important;' +
        'padding-left:0!important;padding-inline-start:0!important;}';
      // Host-level vars are inherited into shadow trees, including closed ones.
      out += ':root,html,body,home-assistant,home-assistant-main,hui-root,partial-panel-resolver{' +
        '--mdc-drawer-width:0px!important;--drawer-width:0px!important;--app-drawer-width:0px!important;}';
      out += 'home-assistant-main,ha-drawer,hui-root{' +
        '--mdc-drawer-width:0px!important;--drawer-width:0px!important;--app-drawer-width:0px!important;}';
    }
    return out;
  }

  function addRoot(root) {
    if (!root) return;
    if (ROOT_SEEN.indexOf(root) >= 0) return;
    ROOT_SEEN.push(root);
    ROOTS.push(root);
  }

  function seedOpenRoots() {
    var q = [document];
    while (q.length) {
      var root = q.shift();
      if (!root) continue;
      var nodes;
      try { nodes = root.querySelectorAll('*'); } catch (e) { continue; }
      for (var i = 0; i < nodes.length; i++) {
        var sr = nodes[i].shadowRoot;
        if (!sr) continue;
        if (ROOT_SEEN.indexOf(sr) >= 0) continue;
        addRoot(sr);
        q.push(sr);
      }
    }
  }

  function hookAttachShadow() {
    if (window.__ksKioskAttachShadowHooked) return;
    var proto = window.Element && window.Element.prototype;
    if (!proto || !proto.attachShadow) return;
    var orig = proto.attachShadow;
    proto.attachShadow = function (init) {
      var sr = orig.call(this, init);
      try {
        addRoot(sr);
        style(sr);
      } catch (e) {}
      return sr;
    };
    window.__ksKioskAttachShadowHooked = true;
  }

  function style(root) {
    if (!root) return;
    var rules = css();
    var el = root.getElementById ? root.getElementById(ID) : null;
    if (!rules) { if (el) el.remove(); return; }
    var host = root;
    if (root.nodeType === 9) {
      host = root.head || root.documentElement;
    }
    if (!host || !host.appendChild) return;
    if (!el) {
      el = document.createElement('style');
      el.id = ID;
      try { host.appendChild(el); } catch (e) { return; }
    }
    if (el.textContent !== rules) el.textContent = rules;
  }

  function closeDrawers() {
    if (!(S.on && S.sidebar && allowedHere())) return;
    for (var r = 0; r < ROOTS.length; r++) {
      var root = ROOTS[r];
      if (!root || !root.querySelectorAll) continue;
      var all = [];
      try { all = root.querySelectorAll('ha-drawer'); } catch (e) { continue; }
      for (var i = 0; i < all.length; i++) {
        try { all[i].removeAttribute('open'); } catch (e) {}
      }
    }
  }

  function applyNow() {
    seedOpenRoots();
    for (var i = 0; i < ROOTS.length; i++) {
      try { style(ROOTS[i]); } catch (e) {}
    }
    closeDrawers();
  }

  // The menu button and the edge swipe both ask the app to open the drawer
  // with this event. Capture phase, so it never reaches the handler.
  window.addEventListener('hass-toggle-menu', function (e) {
    if (S.on && S.sidebar && allowedHere()) {
      e.stopImmediatePropagation();
      if (e.preventDefault) e.preventDefault();
    }
  }, true);

  window.__ksKioskApply = function (on, header, sidebar) {
    S.on = !!on;
    S.header = !!header;
    S.sidebar = !!sidebar;
    applyNow();
    // Home Assistant mounts pieces asynchronously; re-assert briefly.
    setTimeout(applyNow, 60);
    setTimeout(applyNow, 180);
    setTimeout(applyNow, 500);
  };

  // A navigation can mount UI after the URL changed.
  window.addEventListener('location-changed', function () {
    setTimeout(applyNow, 80);
    setTimeout(applyNow, 260);
  });

  hookAttachShadow();
  seedOpenRoots();
})();
''';

/// Turn kiosk mode on or off in the page, live. No-op on a page loaded
/// before the script existed.
String kioskModeApplyJs({
  required bool apply,
  bool hideHeader = true,
  bool hideSidebar = true,
}) =>
    'if (!window.__ksKioskApply) {\n'
    '$kioskModeScript\n'
    '}\n'
    'if (window.__ksKioskApply) window.__ksKioskApply('
    '$apply, $hideHeader, $hideSidebar);';

/// The document-start sources that put kiosk mode on a Home Assistant page
/// shown OUTSIDE the dashboard WebView: a page opened from a dashboard link,
/// a rotation page, a Home Assistant page set as the website screensaver
/// (discussion #225). Those views load whatever address they are given, so
/// this is fenced twice over: the caller only asks for it when the address
/// belongs to this Home Assistant, and [origin] then holds the script to that
/// one origin for the life of the view, so a page that navigates onward to
/// somebody else's site is never touched. On a Home Assistant page that has
/// no header or sidebar to hide there is simply nothing to match.
///
/// Injected whether or not kiosk mode is on, and acting only while the flags
/// say so — the same contract the dashboard uses. These views are built once
/// and kept, so a script injected only while the setting was on would leave
/// the page with no way to hear about the setting being turned on later.
List<String> externalKioskModeSources({
  required String origin,
  required bool apply,
  required bool hideHeader,
  required bool hideSidebar,
}) => [
  'window.__ksKioskOrigins = [${jsonEncode(origin)}];',
  kioskModeScript,
  kioskModeApplyJs(
    apply: apply,
    hideHeader: hideHeader,
    hideSidebar: hideSidebar,
  ),
];
