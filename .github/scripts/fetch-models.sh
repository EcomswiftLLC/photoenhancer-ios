#!/bin/bash
# Downloads the Core ML models from the models-v1 release, compiles them to Models/<name>.mlmodelc (a folder resource in
# project.yml) and copies models-manifest.json. Without the release the app builds and reports the models unavailable.
# release.yml needs the same step before `xcodegen generate`.
set -u
mkdir -p Models
rm -rf .models-download
mkdir -p .models-download
if gh release download models-v1 --repo "${GITHUB_REPOSITORY:-EcomswiftLLC/photoenhancer-ios}" -p '*.zip' -p 'models-manifest.json' -D .models-download; then
  for z in .models-download/*.zip; do
    [ -f "$z" ] && unzip -q -o "$z" -d .models-download/unzipped
  done
  find .models-download/unzipped -maxdepth 3 -name '*.mlpackage' -type d | while read -r pkg; do
    echo "Compiling $pkg"
    xcrun coremlcompiler compile "$pkg" Models/ || echo "::warning::could not compile $pkg"
  done
  cp .models-download/models-manifest.json Models/ 2>/dev/null || true
else
  echo "::notice::No models-v1 release yet: building without models (model tools show as unavailable)."
fi
rm -f Models/README.md
rm -rf .models-download
ls -la Models
du -sh Models || true
