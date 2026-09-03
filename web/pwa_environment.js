(() => {
  "use strict";
  const storageKey = "educflow-web-theme";
  const statusBarColor = "#0D0D10";

  function isIosStandalone() {
    const appleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    return appleMobile && (navigator.standalone === true ||
      window.matchMedia("(display-mode: standalone)").matches);
  }

  function themeColorMeta() {
    let themeColor = document.getElementById("flutterweb-theme");
    if (!themeColor) {
      themeColor = document.createElement("meta");
      themeColor.id = "flutterweb-theme";
      themeColor.name = "theme-color";
      document.head.appendChild(themeColor);
    }
    return themeColor;
  }

  function keepIosStatusBarDark() {
    if (!isIosStandalone()) return;
    const appleStyle = document.querySelector(
      'meta[name="apple-mobile-web-app-status-bar-style"]',
    );
    if (appleStyle && appleStyle.content !== "black") {
      appleStyle.content = "black";
    }
    const themeColor = themeColorMeta();
    if (themeColor.content !== statusBarColor) {
      themeColor.content = statusBarColor;
    }
  }

  function setTheme(dark) {
    const color = dark ? "#0D0D10" : "#F5F7FB";
    const scheme = dark ? "dark" : "light";
    document.documentElement.style.setProperty("--educflow-background", color);
    document.documentElement.style.colorScheme = scheme;
    document.querySelector('meta[name="color-scheme"]').content = scheme;
    // El fondo inicial acompaña al tema de la app. En la PWA de iOS, la barra
    // del sistema permanece oscura independientemente de este valor.
    themeColorMeta().content = isIosStandalone() ? statusBarColor : color;
    try {
      localStorage.setItem(storageKey, scheme);
    } catch (_) {
      // El almacenamiento puede estar deshabilitado; la interfaz sigue funcionando.
    }
  }

  function configureViewport() {
    // El motor sustituye el viewport de index.html durante initializeEngine().
    // Conservamos su configuración de zoom y añadimos únicamente viewport-fit.
    const viewport = document.querySelector('meta[name="viewport"]');
    const settings = viewport.content.split(",")
      .map(value => value.trim())
      .filter(value => value && !value.startsWith("viewport-fit="));
    viewport.content = [...settings, "viewport-fit=cover"].join(", ");
  }

  function getSafeArea() {
    const probe = document.getElementById("educflow-safe-area");
    if (!probe) return [0, 0, 0, 0];
    const style = getComputedStyle(probe);
    return [style.paddingLeft, style.paddingTop, style.paddingRight, style.paddingBottom]
      .map(value => Math.max(0, parseFloat(value) || 0));
  }

  window.educflowPwa = { setTheme, configureViewport, getSafeArea };
  let dark = false;
  try {
    dark = localStorage.getItem(storageKey) === "dark";
  } catch (_) {
    // El tema público por defecto de EducFlow AI es claro.
  }
  setTheme(dark);
  keepIosStatusBarDark();

  // Flutter puede actualizar o recrear theme-color. En iOS instalado se
  // restablece el valor fijo sin interferir con Android ni con el tema interno.
  if (isIosStandalone()) {
    new MutationObserver(keepIosStatusBarDark).observe(document.head, {
      attributes: true,
      attributeFilter: ["content"],
      childList: true,
      subtree: true,
    });
  }
})();
