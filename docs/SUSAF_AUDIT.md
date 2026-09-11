# Sus'AF repository audit and implementation plan

Audit date: 2026-09-11

## Baseline

- Base repository: `fgjaee/ReSuSFS`
- Upstream repository: `ahmed-alnassif/ReSuSFS`
- Base branch: `dev`
- Sus'AF development branch: `susaf-dev`
- Audited commit: `b788daae42044410333a4a07cdd02f60526b0c69`
- Divergence at branch creation: 0 commits ahead, 0 commits behind upstream
- Fork default-branch policy commit: `e4923307100152aafecefcb19561f09cdbb0d3e4`
- Donor/reference only: `rrr333nnn333/BRENE` at `4446d54509e9d571aaaef0b165e89cb23b9ade28`

`upstream/dev` is the pristine upstream reference. The fork's default `dev`
branch carries only the narrow public-surface policy patch that removes the
KernelSU Next dispute copy and upstream donation prompts. Sus'AF product
changes belong on `susaf-dev`; upstream changes are merged explicitly so that
policy conflicts stay visible. BRENE code is not a second base and must not be
merged wholesale.

## Non-negotiable preserved behavior

| Area | Required invariant |
| --- | --- |
| WebUI | Keep the ReSuSFS Vite/Material WebUI architecture and existing Home, SuSFS, UserHub, and More functions. |
| UserHub | Preserve custom `.sh` files, metadata, editor/import behavior, cron schedules, and both boot-stage lists. |
| Boot stages | Preserve `post-fs-data` and `boot-completed` scheduling. Do not silently move a user script between stages. |
| Max Saturation | Preserve the user's Max Saturation script byte-for-byte through migration and keep its current schedule. It is not present in git and therefore must be treated as device data. |
| Uname | Keep the current ReSuSFS generated uname behavior unless the user explicitly selects a custom uname. |
| SUS_MAP | Apply only explicit or narrowly derived targets. Never add every module `.so` file. |
| PTYs | Do not enumerate and hide every `/dev/pts/*` node. |

## High-priority findings

### P0: updater is an executable supply-chain risk

`module/utils.sh` downloads a moving-branch `ksu_susfs` executable, disables
TLS certificate checking, checks only that the response is non-empty, and
then replaces the installed binary. Both installation and the module action
invoke this path. A truncated, substituted, or incompatible executable can be
installed as root.

Required correction:

1. Never use `--no-check-certificate`.
2. Download to a private temporary file with restrictive permissions.
3. Use an immutable release URL and verify a pinned SHA-256 digest or an
   embedded-public-key signature before execution.
4. Probe version/variant compatibility before replacement.
5. Install atomically, retain one known-good backup, and restore it on failure.
6. Show source, expected digest, actual digest, and rollback state in
   diagnostics without exposing secrets.

### P0: WebUI restore extracts an untrusted archive as root

`webui/utils/backup.js` extracts a selected `tar.gz` directly into the
persistent directory. There is no path, link, type, size, or manifest
validation. A malicious archive can use traversal or symlink entries to write
outside the configuration directory.

Required correction:

1. List and validate every archive member before extraction.
2. Reject absolute paths, `..`, empty names, device nodes, FIFOs, hard links,
   and symlinks.
3. Enforce an entry count and extracted-size limit.
4. Extract into a staging directory, validate the expected allowlist, then
   merge with collision backups.
5. Never delete the current configuration until the staged restore passes.

### P0: release metadata still installs upstream ReSuSFS

`module/module.prop`, `update.json`, `module/common/repo.json`, the release
workflow, and WebUI links point to the upstream project. After the identity
change this would offer or install ReSuSFS artifacts over Sus'AF.

The first implementation slice must change the external identity to:

- display name: `Sus'AF`
- module id: `susaf`
- persistent directory: `/data/adb/SusAF`
- primary CLI name: `SusAF`
- release/update URLs: the Sus'AF fork

Keep a `ReSuSFS` CLI compatibility link for existing UserHub scripts. Keep
upstream history and acknowledgements intact instead of globally rewriting
every historical ReSuSFS reference.

### P1: cmdline/bootconfig data accumulates and is not fully sanitized

`ReSuSFS_apply-cmdline-bootconfig.sh` dumps the live proc file to a temporary
file and passes it to `--apply-cmdline-bootconfig`. That command calls
`append_to_default`, so each boot merges the generated snapshot into the
persistent file line-by-line. Changed values can leave mutually inconsistent,
stale entries behind.

The current script changes only three known unlocked-state values. It does not
remove live `androidboot.verifiedbooterror` or
`androidboot.verifyerrorpart` entries even though the template comments tell
the user to remove them.

Required correction:

- Generate one fresh file per apply from the real proc source.
- Normalize the current values instead of matching only one exact old value.
- Remove both error keys for bootconfig and cmdline formats.
- Apply the generated file directly; never append it to user configuration.
- Keep a separate explicit custom-file path for advanced users.
- Use a same-directory temporary file plus atomic rename for any persisted
  generated output.

### P1: current mount hiding is not KernelSU kernel umount support

`ReSuSFS_apply-mount-hiding.sh` scans `/proc/mounts` and sends discovered mount
paths to SuSFS `add_sus_path_loop`. It does not populate KernelSU's kernel
umount list, does not notify KernelSU that module mounts are ready, and can
miss module overlays whose mount source is reported as `KSU` rather than a
`/data/adb/modules/*` path.

The current `ReSuSFS_apply-ksu-settings.sh` then runs
`ksud feature set 1 0`, which disables `kernel_umount` by numeric ID. That is
the opposite of proper support and is fragile across implementations.

Required correction:

- Address the feature by name: `kernel_umount`.
- Check `ksud feature check kernel_umount` and degrade visibly when unsupported.
- Make feature control explicit and tri-state: unchanged, enabled, disabled.
- When enabled, parse `/proc/1/mountinfo`, add narrowly identified KSU/SuSFS
  overlay targets with `ksud kernel umount add --flags 2`, and call
  `ksud kernel notify-module-mounted` after the list is prepared.
- Do not wipe the global kernel umount list; other modules may own entries.
- Keep a user-maintained kernel umount list and log every accepted/rejected
  target for diagnostics.
- Do not copy BRENE's high-mount-ID regex as the sole detector. Mount IDs are
  an implementation detail; validate source, mountpoint, and filesystem data.

### P1: Developer Options/ADB is destructive and has no mode model

The built-in settings script always writes these values to zero:

- `development_settings_enabled`
- `adb_enabled`
- `adb_wifi_enabled`

This is actual state mutation, not a harmless spoof, and it can break the
user's debugging access.

Required modes:

| Mode | Behavior |
| --- | --- |
| `unchanged` | Do not write settings, properties, USB functions, or adbd state. This is the migration-safe default. |
| `spoof-off` | Hide the exposed developer/debug indicators supported by the active stack while preserving the working ADB transport. Refuse the mode if that cannot be done safely on the detected build. |
| `disable` | Intentionally disable USB and wireless debugging and verify that adbd stopped. Require an explicit WebUI confirmation. |

The implementation must snapshot the before/after settings and service state
in diagnostics. It must not claim `spoof-off` succeeded merely because it set
`adb_enabled=0`.

### P1: broad PTY and map hiding should be removed from defaults

The default path script adds every existing `/dev/pts/*` node to
`add_sus_path_loop`. This can hide legitimate terminals and interfere with
shells or debugging. Remove this enumeration; only explicit user entries may
target a PTY.

The default map script runs `find /data/adb/modules -name "*.so"` and adds
every result. It also adds every module font file. This is overly broad and
can create breakage without meaningfully hiding in-memory hooks. Replace it
with the existing explicit `sus_maps.txt` model plus narrowly documented
opt-in discovery rules.

### P1: status reporting rewrites installed module files every five seconds

`service.sh` loops forever and rewrites `module.prop` every five seconds.
This creates needless writes, makes the installed module differ continuously
from its release artifact, and provides no durable structured diagnostic
state.

Replace this with event/stage-based status snapshots under
`/data/adb/SusAF/state/`, and use KernelSU's description override when
available. A low-frequency compatibility fallback may update `module.prop`
only when the rendered value changes.

### P2: Home invokes a nonexistent CLI flag

The Home page calls `--force-update`, but `ReSuSFS.sh` has no matching case.
It falls through to help output. The Sus'AF updater must provide a real,
verified operation or remove the button until that operation exists.

### P2: metadata JSON is invalid

`module/common/repo.json` has a trailing comma after `"KernelSU"`. Strict JSON
parsers will reject it. Fix this in the identity/release slice.

## Diagnostics page scope

Add a dedicated diagnostics route reachable from More. It should be useful
offline and must not change state merely by opening it.

Minimum report:

- Sus'AF/module/KernelSU/SuSFS versions and binary locations
- enabled SuSFS features and `kernel_umount` supported/current/configured state
- boot-stage last-start, last-finish, duration, and exit status
- persistent-path ownership/permissions and migration provenance
- counts plus malformed entries for each managed list
- kernel umount candidates, additions, skips, and failures
- real proc source selected for cmdline/bootconfig and presence of error keys
- real `/proc/version` value and effective uname values
- configured Developer Options/ADB mode plus settings, USB, Wi-Fi, and adbd state
- targeted SUS_MAP and PTY entry counts
- updater source, verification status, digest, last result, and rollback status
- one-tap export to a timestamped text file in Downloads

Use text nodes for collected command output; do not inject diagnostic output
through `innerHTML`.

## Safe persistent configuration migration

Migration is one-way copy/translation into `/data/adb/SusAF`; it never deletes
or mutates `/data/adb/ReSuSFS` or `/data/adb/susfs4ksu`.

### Source priority

1. Existing `/data/adb/SusAF` values always win.
2. Missing values are imported from `/data/adb/ReSuSFS`.
3. Still-missing, explicitly understood values may be translated from
   `/data/adb/susfs4ksu`.

Each source is snapshotted under a timestamped migration directory before
translation. A versioned marker makes reruns idempotent. Conflicts are copied
to a review area rather than overwritten.

### ReSuSFS mapping

| ReSuSFS data | Sus'AF handling |
| --- | --- |
| `scripts/*.sh` | Copy byte-for-byte; preserve names and executable bits. |
| `scripts_postfs.txt` | Copy/merge exact enabled names without changing stage. |
| `scripts_bootcompleted.txt` | Copy/merge exact enabled names without changing stage. |
| `scripts_cron.txt`, `crontabs/` | Preserve the declarative schedule file; regenerate crontab under Sus'AF rather than trusting copied runtime state. |
| `.webui_config/` | Copy user CSS/background files with type and size checks. |
| Supported `.txt` configs | Copy user content, then update only known built-in script references needed for the new CLI/path. |
| Logs/temp/runtime files | Archive for review; do not activate as configuration. |

Custom scripts are not search-and-replaced. The compatibility `ReSuSFS` CLI
link prevents breaking scripts that call the old command. Any script that
hardcodes the old persistent directory is reported for manual review.

### susfs4ksu mapping

| susfs4ksu data | Sus'AF handling |
| --- | --- |
| `sus_path.txt` | Translate valid path entries to `sus_paths.txt`; strip the old optional retry field without losing the original snapshot. |
| `sus_path_loop.txt` | Translate valid path entries to `sus_paths_loop.txt`. |
| `sus_maps.txt` | Import explicit valid paths only. |
| `try_umount.txt` | Translate to a dedicated KernelSU umount list with detach flags. |
| `sus_mount.txt` | Keep in the review snapshot until Sus'AF has explicit `add_sus_mount` support. |
| `sus_open_redirect.txt` | Do not blindly import: its third field is execution stage, while ReSuSFS expects a UID scheme. Translate only after stage and scheme are both resolved. |
| `sus_kstat_statically.json` | Validate and translate known fields; quarantine malformed or partial objects. |
| `config.sh` | Parse known scalar keys only. Never source the legacy file during installation. |
| `legit_mounts.txt` | Use only as an optional exclusion reference for auto-derived mount candidates. |

## Implementation slices

1. **Identity and migration foundation**
   - external Sus'AF identity, dynamic module paths, compatibility CLI
   - `/data/adb/SusAF` schema, state/log directories, safe idempotent migration
   - fork release/update metadata
2. **Bootconfig and property sanitation**
   - clean ephemeral generation, error-key removal, no accumulated data
   - preserve current uname behavior
3. **Kernel umount and mount classification**
   - named feature detection/control, mountinfo parser, explicit list support
   - remove the old mount-to-sus-path substitution
4. **Safe hiding defaults**
   - remove blanket PTY enumeration and blanket `.so`/font discovery
   - retain explicit UserHub/SuSFS list controls
5. **Developer Options/ADB modes**
   - safe default, capability checks, confirmation for destructive disable
6. **Diagnostics**
   - structured stage state and read-only WebUI diagnostics/export
7. **Secure updates and restore**
   - authenticated/pinned binary update with atomic rollback
   - staged, validated config restore
8. **Release hardening**
   - shell/static checks, WebUI lint/build, reproducible zip, checksums,
     migration fixtures, and device-side smoke checklist

Each slice should remain a focused commit or short commit series so upstream
conflicts are localized and individual behavior can be reverted safely.

## Upstream sync procedure

```sh
git fetch --prune upstream
git switch dev
git merge --no-ff upstream/dev
# Resolve README, FUNDING, and WebUI support-card conflicts by preserving the
# fork's neutral language and absence of upstream donation prompts.
git push origin dev
git switch susaf-dev
git merge --no-ff dev
```

Run the full build/test suite after the merge and resolve conflicts on
`susaf-dev`. Apart from the narrow public-surface policy, do not make Sus'AF
product commits on `dev`, and do not force-push either published branch solely
to make the history look linear.
