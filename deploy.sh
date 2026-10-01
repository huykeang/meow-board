#!/usr/bin/env bash
# Tag the current main commit and push that tag to origin.
# This file is safe to keep in the public repository. It stores no credentials.
# Pushing the tag still requires permission to write to origin.
set -euo pipefail

usage() {
    echo "Usage: deploy.sh <patch|minor|major|X.Y.Z> [--title TEXT] [--description TEXT]" >&2
    exit 1
}

valid_part() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

valid_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    local major minor patch
    IFS=. read -r major minor patch <<<"$1"
    valid_part "${major}" && valid_part "${minor}" && valid_part "${patch}"
}

request=""
title=""
description=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)
            if [[ $# -lt 2 || -z "${2}" ]]; then
                usage
            fi
            title="$2"
            shift 2
            ;;
        --description)
            if [[ $# -lt 2 || -z "${2}" ]]; then
                usage
            fi
            description="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage
            ;;
        *)
            if [[ -n "${request}" ]]; then
                usage
            fi
            request="$1"
            shift
            ;;
    esac
done

if [[ -n "${request}" && $# -gt 0 ]]; then
    usage
fi

if [[ -z "${request}" ]]; then
    usage
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${root}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "deploy.sh must live in the Meowboard git repository." >&2
    exit 1
fi

top="$(git rev-parse --show-toplevel)"
if [[ "${top}" != "${root}" ]]; then
    echo "Run deploy.sh from the Meowboard repository root." >&2
    exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${branch}" != "main" ]]; then
    echo "Deploy from main." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean." >&2
    exit 1
fi

git fetch origin --tags

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse origin/main)"
if [[ "${local_head}" != "${remote_head}" ]]; then
    echo "main does not match origin/main. Push or pull before deploying." >&2
    exit 1
fi

if [[ "${request}" == v* ]]; then
    request="${request#v}"
fi

highest=""
while IFS= read -r tag; do
    if [[ "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        highest="${tag}"
        break
    fi
done < <(git tag -l 'v*' --sort=-v:refname)

case "${request}" in
    patch|minor|major)
        if [[ -z "${highest}" ]]; then
            echo "No release yet. Pass an explicit version, for example 1.0.0." >&2
            exit 1
        fi
        IFS=. read -r major minor patch <<<"${highest#v}"
        major=$((10#${major}))
        minor=$((10#${minor}))
        patch=$((10#${patch}))
        case "${request}" in
            patch) patch=$((patch + 1)) ;;
            minor) minor=$((minor + 1)); patch=0 ;;
            major) major=$((major + 1)); minor=0; patch=0 ;;
        esac
        version="${major}.${minor}.${patch}"
        ;;
    *)
        if ! valid_version "${request}"; then
            usage
        fi
        version="${request}"
        ;;
esac

if [[ -n "${highest}" ]]; then
    smaller="$(printf '%s\n%s\n' "${highest#v}" "${version}" | sort -V)"
    smaller="${smaller%%$'\n'*}"
    if [[ "${smaller}" != "${highest#v}" || "${version}" == "${highest#v}" ]]; then
        echo "Version ${version} is not newer than ${highest}." >&2
        exit 1
    fi
fi

tag="v${version}"
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "Tag ${tag} already exists." >&2
    exit 1
fi

if [[ -n "${title}" || -n "${description}" ]]; then
    if [[ -z "${title}" ]]; then
        title="${tag}"
    fi
    if [[ -n "${description}" ]]; then
        git tag -a "${tag}" -m "${title}" -m "${description}"
    else
        git tag -a "${tag}" -m "${title}"
    fi
else
    git tag "${tag}"
fi
git push origin "refs/tags/${tag}"
echo "Tagged ${tag} and pushed it. The release workflow will publish meowboard.tar.gz."
