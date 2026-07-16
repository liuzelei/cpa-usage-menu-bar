#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
workflow="$root_dir/.github/workflows/release.yml"

[[ -f "$workflow" ]]
rg -q 'tags:' "$workflow"
rg -q 'workflow_dispatch:' "$workflow"
rg -q 'matrix:' "$workflow"
rg -q 'arch: \[arm64, x86_64\]' "$workflow"
rg -Fq 'APP_ARCHS: ${{ matrix.arch }}' "$workflow"
rg -q 'APPLE_CERTIFICATE_BASE64' "$workflow"
rg -q 'APPLE_APP_SPECIFIC_PASSWORD' "$workflow"
rg -q 'codesign' "$workflow"
rg -q './scripts/package-dmg.sh' "$workflow"
rg -Fq 'codesign --force --timestamp \' "$workflow"
rg -Fq '"$dmg"' "$workflow"
rg -q 'notarytool submit "\$dmg"' "$workflow"
rg -q 'stapler staple "\$dmg"' "$workflow"
rg -q 'spctl --assess --type open' "$workflow"
rg -q 'grep -q .*accepted' "$workflow"
rg -Fq 'dmg="CPA-Usage-$version-${{ matrix.arch }}.dmg"' "$workflow"
rg -q 'for arch in arm64 x86_64' "$workflow"
rg -q 'needs: package' "$workflow"
rg -q 'gh release create' "$workflow"
rg -Fq 'shell: zsh {0}' "$workflow"
if rg -q 'CPA-Usage-.*\.zip|ditto -c -k' "$workflow"; then
    print -u2 'Release workflow must not package a Universal ZIP'
    exit 1
fi
if rg -q 'shell: zsh$' "$workflow"; then
    print -u2 'Bare shell: zsh declarations are not supported by GitHub Actions'
    exit 1
fi

ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), aliases: true)' "$workflow"
