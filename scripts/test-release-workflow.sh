#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
workflow="$root_dir/.github/workflows/release.yml"

[[ -f "$workflow" ]]
rg -q 'tags:' "$workflow"
rg -q 'workflow_dispatch:' "$workflow"
rg -q 'APP_ARCHS: "arm64 x86_64"' "$workflow"
rg -q 'APPLE_CERTIFICATE_BASE64' "$workflow"
rg -q 'APPLE_APP_SPECIFIC_PASSWORD' "$workflow"
rg -q 'codesign' "$workflow"
rg -q 'notarytool submit' "$workflow"
rg -q 'stapler staple' "$workflow"
rg -q 'spctl --assess' "$workflow"
rg -q 'gh release create' "$workflow"
rg -Fq 'shell: zsh {0}' "$workflow"
if rg -q 'shell: zsh$' "$workflow"; then
    print -u2 'Bare shell: zsh declarations are not supported by GitHub Actions'
    exit 1
fi

ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), aliases: true)' "$workflow"
