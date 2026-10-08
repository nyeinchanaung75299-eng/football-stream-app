{{flutter_js}}
{{flutter_build_config}}

// A new release must load its entrypoint even while a previous main.dart.js
// remains in the browser cache. Repeat visits to the same release stay cached.
const bootstrapUrl = document.currentScript?.src;
const version = bootstrapUrl
  ? new URL(bootstrapUrl, document.baseURI).searchParams.get('v') : null;
if (version) {
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) {
      const url = new URL(build.mainJsPath, document.baseURI);
      url.searchParams.set('v', version);
      build.mainJsPath = url.href;
    }
  }
}

try {
  Promise.resolve(_flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
      } catch (_) {
        window.ncaAppBoot?.fail();
      }
    },
  })).catch(() => window.ncaAppBoot?.fail());
} catch (_) {
  window.ncaAppBoot?.fail();
}
