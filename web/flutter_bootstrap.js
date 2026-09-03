{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine();
    window.educflowPwa.configureViewport();
    await appRunner.runApp();
  }
});
