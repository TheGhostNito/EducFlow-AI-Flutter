const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

const web = path.resolve(__dirname, '../../web');
const source = fs.readFileSync(path.join(web, 'pwa_environment.js'), 'utf8');

test('index fija la barra de iOS en negro y conserva viewport-fit', () => {
  const index = fs.readFileSync(path.join(web, 'index.html'), 'utf8');
  assert.match(index, /name="apple-mobile-web-app-status-bar-style" content="black"/);
  assert.match(index, /name="theme-color" content="#0D0D10"/);
  assert.match(index, /viewport-fit=cover/);
});

function environment({ theme = null, storageBlocked = false, iosStandalone = false } = {}) {
  const elements = {
    'flutterweb-theme': { content: '#F5F7FB' },
    'meta[name="color-scheme"]': { content: 'light dark' },
    'meta[name="apple-mobile-web-app-status-bar-style"]': { content: 'black' },
    'meta[name="viewport"]': { content: 'width=device-width, initial-scale=1.0, maximum-scale=5.0' },
    'educflow-safe-area': {},
  };
  const style = { setProperty(key, value) { this[key] = value; } };
  const observers = [];
  const context = vm.createContext({
    window: { matchMedia: () => ({ matches: iosStandalone }) },
    navigator: {
      userAgent: iosStandalone ? 'iPhone' : 'Desktop',
      platform: iosStandalone ? 'iPhone' : 'Win32',
      maxTouchPoints: iosStandalone ? 5 : 0,
      standalone: iosStandalone,
    },
    MutationObserver: class {
      constructor(callback) { observers.push(callback); }
      observe() {}
    },
    document: {
      documentElement: { style },
      querySelector: selector => elements[selector],
      getElementById: id => elements[id],
      createElement: () => ({}),
      head: { appendChild(element) { elements[element.id] = element; } },
    },
    getComputedStyle: () => ({ paddingLeft: '0px', paddingTop: '59px', paddingRight: '0px', paddingBottom: '34px' }),
    localStorage: {
      getItem() { if (storageBlocked) throw Error('blocked'); return theme; },
      setItem(_, value) { if (storageBlocked) throw Error('blocked'); theme = value; },
    },
  });
  vm.runInContext(source, context);
  return {
    context,
    elements,
    style,
    api: context.window.educflowPwa,
    notifyMutation: () => observers.forEach(callback => callback()),
  };
}

test('recupera el fondo oscuro antes de iniciar Flutter y cambia a claro', () => {
  const { api, elements, style } = environment({ theme: 'dark' });
  assert.equal(style['--educflow-background'], '#0D0D10');
  assert.equal(elements['flutterweb-theme'].content, '#0D0D10');
  assert.equal(style.colorScheme, 'dark');
  api.setTheme(false);
  assert.equal(style['--educflow-background'], '#F5F7FB');
  assert.equal(elements['flutterweb-theme'].content, '#F5F7FB');
  assert.equal(style.colorScheme, 'light');
  assert.equal(elements['meta[name="apple-mobile-web-app-status-bar-style"]'].content, 'black');
});

test('la PWA de iOS mantiene la barra oscura al cambiar el tema', () => {
  const { api, elements, style, notifyMutation } = environment({
    iosStandalone: true,
  });
  api.setTheme(false);
  assert.equal(style['--educflow-background'], '#F5F7FB');
  assert.equal(elements['flutterweb-theme'].content, '#0D0D10');
  assert.equal(
    elements['meta[name="apple-mobile-web-app-status-bar-style"]'].content,
    'black',
  );

  // Simula que Flutter vuelve a escribir el meta según el tema claro.
  elements['flutterweb-theme'].content = '#F5F7FB';
  notifyMutation();
  assert.equal(elements['flutterweb-theme'].content, '#0D0D10');
});

test('el almacenamiento bloqueado no impide iniciar ni cambiar el tema', () => {
  const { api, style } = environment({ storageBlocked: true });
  api.setTheme(true);
  assert.equal(style['--educflow-background'], '#0D0D10');
});

test('recrea el meta de tema si una actualización de Flutter lo elimina', () => {
  const { api, elements } = environment();
  delete elements['flutterweb-theme'];
  api.setTheme(true);
  assert.equal(elements['flutterweb-theme'].name, 'theme-color');
  assert.equal(elements['flutterweb-theme'].content, '#0D0D10');
});

test('conserva el zoom del viewport del motor y no duplica viewport-fit', () => {
  const { api, elements } = environment();
  api.configureViewport();
  api.configureViewport();
  assert.equal(elements['meta[name="viewport"]'].content,
    'width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover');
});

test('lee los cuatro insets y tolera que el probe todavía no esté montado', () => {
  const { api, elements } = environment();
  assert.deepEqual(Array.from(api.getSafeArea()), [0, 59, 0, 34]);
  delete elements['educflow-safe-area'];
  assert.deepEqual(Array.from(api.getSafeArea()), [0, 0, 0, 0]);
});

test('el bootstrap restaura el viewport después del motor y antes de runApp', async () => {
  const { context, elements } = environment();
  let options;
  context._flutter = { loader: { load(value) { options = value; } } };
  vm.runInContext(fs.readFileSync(path.join(web, 'flutter_bootstrap.js'), 'utf8')
    .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', ''), context);
  let ran = false;
  await options.onEntrypointLoaded({ async initializeEngine() {
    elements['meta[name="viewport"]'].content = 'width=device-width, maximum-scale=5.0';
    return { async runApp() {
      assert.match(elements['meta[name="viewport"]'].content, /viewport-fit=cover/);
      ran = true;
    } };
  } });
  assert.equal(ran, true);
});
