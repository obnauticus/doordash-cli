#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <linux-binary> [expected-version]" >&2
    exit 2
fi

binary="$(realpath "$1")"
expected_version="${2:-}"

for command in curl file realpath seq timeout; do
    command -v "$command" >/dev/null || {
        echo "Required smoke-test command is missing: $command" >&2
        exit 1
    }
done

temporary_paths=()
cleanup() {
    for temporary_path in "${temporary_paths[@]}"; do
        if [[ -d "$temporary_path" ]]; then
            rm -rf -- "$temporary_path"
        else
            rm -f -- "$temporary_path"
        fi
    done
}
trap cleanup EXIT

[[ -x "$binary" ]] || { echo "Not executable: $binary" >&2; exit 1; }
file "$binary" | grep -q 'ELF 64-bit'

version_output="$($binary --version)"
if [[ -n "$expected_version" ]]; then
    grep -Fq "version $expected_version" <<<"$version_output"
fi

help_output="$($binary --help)"
for command in login search menu store-details item-details \
    restaurant-item-details find-items find-nearby-stores \
    build-grocery-list cart promo order address payment-method; do
    grep -Eq "^[[:space:]]+$command([[:space:]]|$)" <<<"$help_output" || {
        echo "Missing root command in --help: $command" >&2
        exit 1
    }
done

# Exercise browser launch and the localhost OAuth callback server without
# exchanging a real authorization code or persisting credentials.
oauth_stdout="$(mktemp)"
oauth_stderr="$(mktemp)"
callback_body="$(mktemp)"
temporary_paths+=("$oauth_stdout" "$oauth_stderr" "$callback_body")
BROWSER=true timeout --signal=INT --kill-after=1 15 \
    "$binary" login >"$oauth_stdout" 2>"$oauth_stderr" &
oauth_pid=$!
callback_received=0
for _attempt in $(seq 1 100); do
    if curl --silent --fail --output "$callback_body" \
        'http://localhost:4180/oauth2/callback?error=access_denied&error_description=linux-smoke'; then
        callback_received=1
        break
    fi
    sleep 0.1
done
if [[ "$callback_received" -ne 1 ]]; then
    kill "$oauth_pid" 2>/dev/null || true
    wait "$oauth_pid" 2>/dev/null || true
    echo "OAuth callback listener did not become ready." >&2
    exit 1
fi
set +e
wait "$oauth_pid"
oauth_status=$?
set -e
[[ "$oauth_status" -eq 1 ]] || {
    echo "OAuth denial returned unexpected status: $oauth_status" >&2
    exit 1
}
grep -Fq 'You can close this tab' "$callback_body"
grep -Fq 'identity.doordash.com/authorize' "$oauth_stderr"
grep -Fq 'Authentication/Authorization failed' "$oauth_stderr"

# When a build-time Python containing keyring is supplied, exercise the actual
# Linux Secret Service path as well as authenticated command-group loading.
if [[ -n "${KEYRING_PYTHON:-}" ]] && command -v dbus-run-session >/dev/null \
    && command -v gnome-keyring-daemon >/dev/null; then
    smoke_home="$(mktemp -d)"
    temporary_paths+=("$smoke_home")
    export smoke_home binary
    dbus-run-session -- bash -c '
        set -euo pipefail
        export HOME="$smoke_home"
        eval "$(printf linux-smoke-keyring | gnome-keyring-daemon --unlock --components=secrets)"
        "$KEYRING_PYTHON" -c '\''import keyring; keyring.set_password("dd-cli", "oauth-tokens", "{\"access_token\":\"smoke\",\"refresh_token\":\"smoke\",\"expires_at\":4102444800}")'\''
        root_commands=(login search menu store-details item-details
            restaurant-item-details find-items find-nearby-stores
            build-grocery-list cart promo order address payment-method)
        for command in "${root_commands[@]}"; do
            "$binary" "$command" --help >/dev/null
        done

        nested_commands=(
            "cart list" "cart add-items" "cart show" "cart remove-item" "cart delete"
            "promo list" "promo apply" "promo remove"
            "order history" "order reorder" "order receipt" "order status"
            "order preview" "order submit" "order checkout-url"
            "address list" "address set" "payment-method list"
        )
        for command in "${nested_commands[@]}"; do
            read -r -a args <<<"$command"
            "$binary" "${args[@]}" --help >/dev/null
        done
    '
fi

echo "Linux smoke tests passed: $version_output"
