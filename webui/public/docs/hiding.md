# Hiding behavior

Sus'AF uses targeted rules instead of broad filesystem scans.

- KernelSU `kernel_umount` receives validated live KSU/module-backed mountpoints
  and explicit mounted targets. Existing global entries are preserved.
- SUS_PATH and SUS_PATH_LOOP apply only configured paths. PTY nodes are never
  enumerated automatically.
- SUS_MAP applies only entries in `sus_maps.txt`; it does not add every module
  library or every `.so` file.
- Kstat is intended only for paths whose stat identity genuinely changes after
  a bind mount or overlay.
- Verified-boot sanitation removes `verifiedbooterror` and `verifyerrorpart`;
  it does not rewrite build, product, lock-state, Developer Options, or ADB
  properties.

More rules are not automatically better. Broad or contradictory spoofing can
create inconsistencies that are easier to detect and harder to diagnose.
