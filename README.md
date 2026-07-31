# DoorDash CLI

DoorDash CLI (`dd-cli`) is a terminal tool for ordering from DoorDash — search restaurants and stores, browse menus, build a cart, reorder a past order, and preview or check out — all from the command line. It's built to be driven directly by a human, or called by AI agents with shell access (Claude Code, Cursor, Codex, etc.) so they can complete ordering tasks on your behalf.

> Waitlist-only. Full functionality requires an approved account. Join the waitlist here: https://forms.gle/gvCQZvu9C1EKA6aM6

Currently supported: **macOS, Apple Silicon (M1/M2/M3/M4)**.

This repository also contains a community Linux rebuild workflow. It preserves
the official release's packaged Python application bytecode and replaces its
macOS-only runtime and keychain adapter with Linux equivalents. See
[Linux rebuild](#linux-rebuild) below.

## Download

1. Go to the [Releases page](https://github.com/doordash-oss/doordash-cli/releases) and open the latest release.
2. Download the `dd-cli-v<version>-darwin-arm64.tar.gz` asset.
3. Use the SHA256 checksum published on that release to verify the download.
4. Extract the tar.gz and follow the instructions in the `quickstart.txt`.

## Features
DoorDash CLI functionality will become available to you once you have gotten off the waitlist and have signed into a DoorDash account via dd-cli login.

The following subset of DoorDash features are currently supported:
- Addresses: list saved addresses, set the default address (must be a previously registered address)
- Payment methods: list saved payment methods (currently card-only)
- Store Search: search for stores (restaurant, grocery, and more) based on free-form query, find nearby stores, view store details
- Menu Search: browse menus/catalogs, search for specific items, view item details
- Cart management: list active carts, add/remove items, view cart contents, delete cart
  - Cart Types: Individual or Group
- Shopping list: Build cart from a shopping list
- Promotions: list eligible campaign promos for a store, apply/remove promo code
- Work benefits: apply company/employee payment budgets
- Ordering: preview order pricing, set tip amount, apply credits, submit orders (or get a browser checkout URL as fallback), check payment status, recreate a past order
  - Fulfillment modes: Pick-up or Delivery
  - Scheduling: ASAP or Schedule Ahead
  - Delivery Speed: Priority/Express or Standard
- Order history: view past orders and fetch receipts

## Security Notice

This binary is distributed as-is, without warranty of any kind. By downloading and executing it, you acknowledge that you are running third-party software obtained over the internet and assume all associated risks. We strongly recommend verifying the integrity of the downloaded file before use by comparing it against the published checksum associated with the release. Do not proceed if the computed checksum does not match.

To compute the checksum of your download:

```bash
shasum -a 256 dd-cli-v<version>-darwin-arm64.tar.gz
```

## Linux rebuild

On a 64-bit glibc 2.17+ Linux host (x86_64 or aarch64), run:

```bash
bash scripts/rebuild-linux.sh
```

The script selects the latest official macOS ARM64 release, verifies its
published SHA256 digest, extracts the architecture-neutral Python package,
recreates its exact dependency set on a matching Linux Python runtime, builds
a native executable against the manylinux2014 baseline, audits its bundled ELF
libraries, exercises its command surface and Linux Secret Service credential
path, and writes a binary plus installable archive under `dist/`. To rebuild a
specific release, pass its version:

```bash
bash scripts/rebuild-linux.sh 0.2.1
```

The resulting CLI requires an unlocked Secret Service-compatible desktop
keychain (for example GNOME Keyring). This matches the official CLI's rule that
OAuth credentials must use an operating-system keychain; no plaintext token
fallback is introduced.

### Headless SSH sign-in

The OAuth redirect is fixed to `http://localhost:4180/oauth2/callback`. When
the browser and `dd-cli` run on different machines, forward that address from
the browser machine to the Linux host. In a second terminal on the browser
machine, keep this running (substitute the same destination used for SSH):

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 4180:127.0.0.1:4180 \
  <user>@<linux-host>
```

On a headless Linux host, start a D-Bus shell first if the SSH session does not
already have `DBUS_SESSION_BUS_ADDRESS`, then unlock GNOME Keyring without
putting its password in shell history:

```bash
dbus-run-session -- bash  # only when DBUS_SESSION_BUS_ADDRESS is unset
read -rsp "Keyring password: " dd_keyring_password; echo
eval "$(printf '%s' "$dd_keyring_password" | \
  gnome-keyring-daemon --unlock --components=secrets)"
unset dd_keyring_password
dd-cli login
```

Open the printed authorization URL on the browser machine. Its localhost
callback travels through the SSH tunnel to the waiting CLI. Keep the D-Bus
shell open for subsequent commands; an SSH session using public-key auth does
not normally unlock the login keyring through PAM.

### Optional 1Password credential storage

For a headless host, the Linux build can replace Secret Service with the
installed [1Password CLI](https://developer.1password.com/docs/cli/). This is
opt-in; the default remains the operating-system keychain. Sign `op` in and
choose a vault explicitly, then export the non-secret backend configuration
for `login` and every later command:

```bash
op signin --account <account>
op whoami
export DD_CLI_CREDENTIAL_BACKEND=1password
export DD_CLI_1PASSWORD_VAULT='<vault name or ID>'
# Optional when more than one account is configured:
export DD_CLI_1PASSWORD_ACCOUNT='<account shorthand or ID>'
dd-cli login
```

On first successful login, the backend creates a Password item titled
`dd-cli OAuth Tokens`; override that non-secret title with
`DD_CLI_1PASSWORD_ITEM` if needed. The OAuth document is sent to `op` over
stdin and stored only in the concealed password field—never in command
arguments, environment variables, or temporary files. The `op` session must
remain authenticated when running subsequent `dd-cli` commands. The SSH port
forward above is still required when the browser runs elsewhere.

## Try it

```bash
dd-cli --help
dd-cli search --query "ramen near me"
dd-cli order history
```
