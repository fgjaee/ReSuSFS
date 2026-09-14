# Sus'AF upstream sync procedure

Sus'AF keeps ReSuSFS ancestry while treating `susaf-dev` as the canonical
product branch. Never reset or rebase `susaf-dev` onto upstream.

## Remotes and branches

- `origin`: the Sus'AF repository and only push destination.
- `upstream`: the ReSuSFS repository; its push URL must remain disabled.
- `susaf-dev`: canonical Sus'AF development branch.
- `sync/upstream-YYYYMMDD`: disposable integration branch for one upstream
  merge.

## Start a sync

```sh
git fetch --prune upstream
git switch susaf-dev
git pull --ff-only origin susaf-dev
git tag backup/pre-upstream-YYYYMMDD
git switch -c sync/upstream-YYYYMMDD
git merge --no-commit --no-ff upstream/dev
```

Do not resolve every conflict with one blanket `--ours` or `--theirs` action.
Review each conflict according to the protected surfaces below.

## Resolution policy

Always preserve Sus'AF's module ID, display name, persistent path, migration,
secure updater, KernelSU integration, boot stages, UserHub/custom scripts,
Max Saturation scheduling, targeted hiding, diagnostics, and release metadata.

`README.md`, `CHANGELOG.md`, `module/module.prop`, `update.json`, funding files,
and release workflows must retain Sus'AF identity and policy. Upstream donation
links, root-manager disputes, recommendations, version bumps, and ReSuSFS
branding are not imported.

Neutral fixes may be adapted after review. Typical candidates are WebUI bug
fixes, dependency maintenance, translation infrastructure, and translations.
Translations must be checked for stale branding, links, and strings that no
longer match Sus'AF behavior.

## Validate before integration

```sh
for test in tests/test-*.sh; do sh "$test"; done
(cd webui && pnpm lint && pnpm build)
git diff --check
```

Run the release safety scan and build twice with the same source timestamp;
the two ZIP digests must match. Complete the device smoke test for changes that
affect installation, boot, root-manager calls, SuSFS behavior, or migration.

After review and validation, commit the upstream merge on the sync branch,
merge that branch into `susaf-dev`, and push only to `origin`. Keeping the merge
commit preserves upstream ancestry and makes the next sync easier. Git rerere
should remain enabled so proven conflict resolutions can be reused.
