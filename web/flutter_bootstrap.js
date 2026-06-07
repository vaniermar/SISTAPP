{{flutter_js}}
{{flutter_build_config}}

const buildTag = Date.now().toString();
_flutter.buildConfig.builds = _flutter.buildConfig.builds.map((build) => {
  if (!build.mainJsPath) {
    return build;
  }
  return {
    ...build,
    mainJsPath: `${build.mainJsPath}?v=${buildTag}`,
  };
});

_flutter.loader.load();
