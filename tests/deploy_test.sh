#!/usr/bin/env bash
# Exercises deploy.sh against temporary repositories. It does not tag this checkout.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_source="${project_root}/deploy.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

git_user=(-c user.name=Meowboard -c user.email=meowboard@example.com)

commit_all() {
    local work="$1"
    local message="$2"
    git -C "${work}" add -A
    git -C "${work}" "${git_user[@]}" commit -m "${message}" >/dev/null
}

make_repo() {
    local name="$1"
    local origin="${test_root}/${name}.git"
    local work="${test_root}/${name}"
    git init --bare -b main "${origin}" >/dev/null 2>&1
    git init -b main "${work}" >/dev/null 2>&1
    git -C "${work}" remote add origin "${origin}"
    printf 'meow\n' > "${work}/README"
    cp "${deploy_source}" "${work}/deploy.sh"
    chmod 755 "${work}/deploy.sh"
    commit_all "${work}" "init"
    git -C "${work}" push -u origin main >/dev/null
    printf '%s' "${work}"
}

tag_repo() {
    local work="$1"
    local tag="$2"
    git -C "${work}" tag "${tag}"
    git -C "${work}" push origin "refs/tags/${tag}" >/dev/null
}

run_deploy() {
    local work="$1"
    shift
    bash "${work}/deploy.sh" "$@"
}

expect_failure() {
    local work="$1"
    shift
    local status=0
    bash "${work}/deploy.sh" "$@" >/dev/null 2>&1 || status=$?
    [[ "${status}" -ne 0 ]]
}

remote_tags() {
    local work="$1"
    git -C "${work}" ls-remote --tags origin
}

assert_remote_tag() {
    local work="$1"
    local tag="$2"
    remote_tags "${work}" | grep -q "refs/tags/${tag}$"
}

work="$(make_repo explicit)"
run_deploy "${work}" 1.0.0
assert_remote_tag "${work}" v1.0.0

work="$(make_repo titled)"
GIT_COMMITTER_NAME=Meowboard \
GIT_COMMITTER_EMAIL=meowboard@example.com \
run_deploy "${work}" 1.0.0 \
    --title "Header search" \
    --description "Search sits on the top left."
assert_remote_tag "${work}" v1.0.0
origin="$(git -C "${work}" remote get-url origin)"
subject="$(git -C "${origin}" for-each-ref refs/tags/v1.0.0 --format='%(contents:subject)')"
body="$(git -C "${origin}" for-each-ref refs/tags/v1.0.0 --format='%(contents:body)')"
body="${body%$'\n'}"
[[ "${subject}" == "Header search" ]]
[[ "${body}" == "Search sits on the top left." ]]

work="$(make_repo minor)"
tag_repo "${work}" v1.0.0
run_deploy "${work}" minor
assert_remote_tag "${work}" v1.1.0

work="$(make_repo patch)"
tag_repo "${work}" v1.1.0
run_deploy "${work}" patch
assert_remote_tag "${work}" v1.1.1

work="$(make_repo major)"
tag_repo "${work}" v1.1.1
run_deploy "${work}" major
assert_remote_tag "${work}" v2.0.0

work="$(make_repo ten)"
tag_repo "${work}" v1.9.0
tag_repo "${work}" v1.10.0
run_deploy "${work}" patch
assert_remote_tag "${work}" v1.10.1

work="$(make_repo dirty)"
printf 'dirty\n' >> "${work}/README"
expect_failure "${work}" minor
[[ -z "$(remote_tags "${work}")" ]]

work="$(make_repo unpushed)"
printf 'local\n' >> "${work}/README"
commit_all "${work}" "local only"
expect_failure "${work}" 1.0.0
[[ -z "$(remote_tags "${work}")" ]]

work="$(make_repo first-bump)"
expect_failure "${work}" minor
[[ -z "$(remote_tags "${work}")" ]]

work="$(make_repo older)"
tag_repo "${work}" v1.2.0
expect_failure "${work}" 1.0.0
remote_tags "${work}" | grep -q 'refs/tags/v1.2.0$'
if remote_tags "${work}" | grep -q 'refs/tags/v1.0.0$'; then
    echo "older version was published" >&2
    exit 1
fi

echo "deploy tests passed"
