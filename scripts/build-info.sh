#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
#
# Sourced by build-app.sh and build-pro.sh. Works out what is being built, for the Info.plist:
#   TF_CHANNEL  "alpha" (test build: the app shows a strip with these details) or "release" (no strip;
#               details only in the log). Default: release on a clean main branch, alpha otherwise.
#               package.sh and release-pro.sh force "release".
#   TF_BRANCH, TF_COMMIT, TF_PR, TF_BUILD_TIME, TF_BUILD (build number)
# Any of them can be set beforehand to override, e.g. TF_PR=9 TF_BRANCH=fix-x scripts/build-pro.sh

TF_BRANCH=${TF_BRANCH:-${GITHUB_HEAD_REF:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}}
if [[ -z "${TF_COMMIT:-}" ]]; then
  TF_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
  [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]] && TF_COMMIT="$TF_COMMIT+changes"
fi
# PR number: explicit, from GitHub Actions (refs/pull/<n>/merge), or from gh for the current branch.
if [[ -z "${TF_PR:-}" ]]; then
  if [[ "${GITHUB_REF:-}" == refs/pull/*/merge ]]; then
    TF_PR=${${GITHUB_REF#refs/pull/}%/merge}
  else
    TF_PR=$(gh pr view "$TF_BRANCH" --json number --jq .number 2>/dev/null || true)
  fi
fi
TF_BUILD_TIME=${TF_BUILD_TIME:-$(date '+%Y-%m-%d %H:%M %Z')}
TF_BUILD=${TF_BUILD:-$(date '+%Y%m%d%H%M')}
if [[ -z "${TF_CHANNEL:-}" ]]; then
  if [[ "$TF_BRANCH" == main && "$TF_COMMIT" != *+changes && -z "$TF_PR" ]]; then TF_CHANNEL=release; else TF_CHANNEL=alpha; fi
fi
export TF_CHANNEL TF_BRANCH TF_COMMIT TF_PR TF_BUILD_TIME TF_BUILD

# Info.plist lines for these values (inserted into the app's plist by the build scripts).
TF_PLIST_KEYS="	<key>TFBuildChannel</key><string>$TF_CHANNEL</string>
	<key>TFBuildBranch</key><string>$TF_BRANCH</string>
	<key>TFBuildCommit</key><string>$TF_COMMIT</string>
	<key>TFBuildPR</key><string>$TF_PR</string>
	<key>TFBuildTime</key><string>$TF_BUILD_TIME</string>"
echo "==> Build: $TF_CHANNEL, ${TF_PR:+PR #$TF_PR, }$TF_BRANCH @ $TF_COMMIT, build $TF_BUILD, $TF_BUILD_TIME"
