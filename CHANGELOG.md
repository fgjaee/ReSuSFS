# Sus'AF Changelog

This changelog covers Sus'AF development. Upstream history remains available in
Git history and the upstream project; it is not repeated here.

## v0.1.0-dev.4 — 2026-09-13

- Made empty Open Redirect configuration report that the optional feature is
  off instead of opening a blank action screen. Silent actions now receive a
  generic terminal message as a final fallback.
- Added an upgrade repair that recoverably archives cmdline/bootconfig files
  larger than the kernel interface's 8,191-byte limit and restores the clean
  template; normal boot continues to generate a fresh sanitized snapshot.
- Stopped the built-in Sus Kstat task from appending generated module paths to
  persistent user configuration. Known generated ReSuSFS/SusAF entries are
  archived and removed on upgrade, and missing targets are skipped cleanly.

## v0.1.0-dev.3 — 2026-09-13

- Bundled the release-pinned, digest-verified `ksu_susfs` binary so installation
  and recovery no longer depend on a live download.
- Added a module-local executable fallback and support for both KernelSU and
  APatch binary directories, preventing a missing global copy from breaking
  boot scripts or the WebUI status check.
- Removed the leftover Telegram prompt from the WebUI home page.

## v0.1.0-dev.2 — 2026-09-12

- Removed the timed Volume Up/Down installer prompts. Existing configuration
  now wins, packaged schedule entries are merged without duplicates, and
  UserHub stage assignments are preserved.
- Added repair logic for early Sus'AF builds that could replace a migrated
  `scripts_bootcompleted.txt`, including the Max Saturation assignment.
- Rebranded packaged built-ins from `ReSuSFS_*` to `SusAF_*`; known old
  built-ins and schedule files are moved to a recoverable migration archive.
- Changed completed legacy migration to move `/data/adb/ReSuSFS` and
  `/data/adb/susfs4ksu` into
  `/data/adb/SusAF/migration/legacy-sources/` instead of leaving stale top-level
  directories.
- Changed the module display name to typographic `Sus’AF`, avoiding the
  installer parser error caused by the ASCII apostrophe while preserving the
  intended displayed name.
- Replaced the inherited changelog with project-neutral Sus'AF release notes.
- Kept the `ReSuSFS` command only as a compatibility entry point for migrated
  UserHub scripts.

## v0.1.0-dev.1 — 2026-09-12

- Added KernelSU kernel-umount handling and validated targeted mount discovery.
- Added fresh bootconfig generation and verified-boot error sanitation.
- Preserved uname behavior while preventing stale generated data.
- Added explicit Developer Options/ADB policies: `unchanged`, `spoof-off`, and
  confirmed `actually-disable`.
- Removed blanket PTY and shared-library hiding from the defaults.
- Added a private WebUI diagnostics page.
- Added a fail-closed, digest-pinned SuSFS userspace updater.
- Added validated backup/restore and safe legacy configuration import.
