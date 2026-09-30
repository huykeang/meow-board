#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

mkdir -p "${test_root}/archive/meow-board-main" "${test_root}/bin" "${test_root}/home"
cat > "${test_root}/archive/meow-board-main/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "remote bootstrap succeeded"
EOF
tar -czf "${test_root}/meow-board.tar.gz" -C "${test_root}/archive" meow-board-main

cat > "${test_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
expected="https://github.com/huykeang/meow-board/archive/refs/heads/main.tar.gz"
[[ "${1:-}" == "-fsSL" && "${2:-}" == "${expected}" ]]
cat "${TEST_ARCHIVE}"
EOF
chmod 755 "${test_root}" "${test_root}/bin" "${test_root}/bin/curl" "${test_root}/home"
chmod 644 "${test_root}/meow-board.tar.gz"

runner=()
if [[ "${EUID}" -eq 0 ]]; then
    runner=(runuser -u nobody --)
fi

output="$(
    cat "${project_root}/install.sh" |
        "${runner[@]}" env \
            HOME="${test_root}/home" \
            PATH="${test_root}/bin:${PATH}" \
            TEST_ARCHIVE="${test_root}/meow-board.tar.gz" \
            bash
)"

[[ "${output}" == "remote bootstrap succeeded" ]]
echo "install bootstrap test passed"
