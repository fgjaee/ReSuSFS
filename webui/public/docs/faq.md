# Frequently asked questions

## Why does Diagnostics say "already registered"?

The target is already in KernelSU's global umount list. Sus'AF preserves it and
does not add or wipe it again. This is a successful state, not a failure.

## Why are some explicit umount targets inactive?

Kernel umount entries must be current mountpoints. A path such as `/system` or
`/debug_ramdisk` may not be a separate mount on a particular Android build.
Sus'AF records it as not mounted/inactive and leaves it alone.

## Why is Open Redirect empty?

It is optional and disabled when `open_redirect.txt` has no entries.

## Why can a detector still report something?

Some findings come from the kernel, another module, an installed user CA
certificate, or contradictory property spoofing. Diagnostics identifies the
Sus'AF-controlled layers but cannot honestly guarantee every third-party
detector will report a stock environment.

## Why do legacy ReSuSFS or susfs4ksu names appear in migration status?

They identify supported import sources. Completed sources are archived under
`/data/adb/SusAF/migration/legacy-sources` rather than deleted.
