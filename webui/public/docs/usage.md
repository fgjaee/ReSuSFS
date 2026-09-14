# Using Sus'AF

Sus'AF applies its built-in post-fs-data and boot-completed tasks automatically.
Use the SuSFS page to edit or apply individual configuration files. Missing or
empty files mean that the optional feature has no custom entries.

Use UserHub for custom shell scripts. Each script can be assigned independently
to post-fs-data, boot-completed, or an explicit schedule. Imported scripts run
as root, so only import code you trust.

The Diagnostics page shows the active SuSFS binary, KernelSU daemon and feature
states, mount-registration results, boot sanitation, ADB policy, migration,
and updater verification. Refresh creates a new private snapshot; Export saves
a path-free report to Downloads.

Configuration lives under `/data/adb/SusAF`. Backup & Restore exports only
recognized configuration and script files and validates an archive before it
can replace live data.
