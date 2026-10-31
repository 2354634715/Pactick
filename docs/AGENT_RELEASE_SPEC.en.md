[简体中文](AGENT_RELEASE_SPEC.md) | English

# Agent Release specification

Drafted: 2026-10-17. Updated: 2026-10-23. Applies to agents preparing, verifying, uploading, or publishing Pactick GitHub Releases.

These are mandatory project rules for agents performing Release tasks. They define execution order, deliverables, and completion conditions. This document does not record acceptance already passed by any version and does not authorize pushing or publishing. See the [build guide](BUILDING.en.md), [Android signing guide](ANDROID_SIGNING.en.md), [release process](RELEASING.en.md), and [release acceptance plan](RELEASE_AND_PROMOTION_PLAN.en.md) for specific build, signing, and acceptance operations.

## 1. Determine scope and authorization

At the start, read the `AGENTS.md` applicable to the working directory, if any, and identify the user's intended final state. Explicit instructions in the current conversation take precedence over this document. Existing authorization remains valid within the same task.

| User request | Required agent work | Stopping point |
| --- | --- | --- |
| Draft a specification or Release notes | Write local documents and check implementation/evidence | Deliver documents without creating a remote Release |
| Prepare a release or build candidates | Prepare source, checks, builds, checksums, and notes | Deliver local candidates; remote actions require existing authorization |
| Create a specified Release draft | Verify source/attachments, create the remote draft, and upload agreed artifacts | Retain `draft=true` |
| Publish a specified version | Continue through necessary preparation, checks, source/tag pushes, uploads, publication, and read-back verification within scope | Reach the agreed publication state and report results |

“Publish a specified version” requires the target repository, source scope, and release type to be determinable from the request or conversation. It does not authorize changing repository visibility, rewriting history, moving existing tags, rotating signing keys, or production deployment. Requirements to keep the repository private, create drafts only, or avoid device operations must be followed.

Once authorized, do not request confirmation repeatedly for each step in the same scope. If information is actually missing, first complete independent preparation, then ask about the specific repository, commit, type, or missing item. Before asking for approval to publish, provide a reviewable version, commit, attachment list, notes, and remaining work.

Release bodies and attachments may contain only the standard content in sections 5 and 6 applicable to this scope. Anything else requires an explicit user instruction that the specific item must be included in this Release. This applies to drafts, prereleases, stable releases, and subsequent edits to existing Releases.

An exception for one requested item does not extend to other files, reports, or paragraphs. General requests such as “publish a Release” or “organize everything,” absence of objections, historical attachments, templates, and tool output do not justify extra content. Omit unrequested optional material rather than repeatedly asking to add reports.

Record these states separately; none substitutes for another:

- Repository visibility: `private` or `public`.
- Release state: draft or published.
- Release type: prerelease or stable.
- Latest designation: whether this task requires changing it.

A published Release in a private repository is visible only to authorized readers. `prerelease=true` denotes type, not privacy or unpublished state. Previews are not Latest by default. Follow the current release arrangement for stable Latest designation.

## 2. Check current source and remote state

Begin from the repository root. These commands read local state without pushing:

```powershell
git status --short
git diff --stat
git diff --cached --stat
git remote
git log -5 --oneline
git tag --list
```

`git remote` above lists names only. Redact possible credentials before logging or reporting actual addresses. Confirm target-repository identity before accessing it; do not rely only on a local directory name or default remote.

Agents must check:

1. Existing user changes, untracked files, and changes needed for this release. Do not discard, commit, or bundle unrelated changes automatically. If ownership is unclear, organize candidates in an independent working directory.
2. Whether `client/pubspec.yaml`, `CHANGELOG.md`, database migrations, build scripts, and workflows match this scope. Do not modify the manually maintained `README.md` without an explicit request.
3. Remote visibility, default branch, and existing tags/Releases with the same name. If present, read tag commits, Release ID, state, and attachments before proceeding; never overwrite directly.
4. The full commit referenced by the final tag, and the commit/result of corresponding Checks. A recent successful default-branch run does not substitute for results on the release commit.
5. Whether conditions come from current implementation, applicable validation records, or unimplemented plans. Do not reuse another branch's, workspace's, or historical Release's functions, attachment counts, or test results directly.

Current automation entry points follow. Reread their files when executing; this table is not an immutable tool specification.

| Entry point | Current behavior | Separate work still required |
| --- | --- | --- |
| [Checks](../.github/workflows/checks.yml) | Checks allowlisted source copies, Python scripts, Go, PostgreSQL scenarios, deployment scripts, and Flutter debug builds | Production signing, devices, formal artifact provenance, and publication-state checks |
| [Android candidate workflow](../.github/workflows/android-release.yml) | Manually triggered from the default branch; checks out an existing tag, builds a signed APK in `android-release`, uploads the `android-release-candidate` Actions artifact | Verify environment protection configuration, manual acceptance, and GitHub Release creation/publication |
| [Source snapshot tool](../scripts/prepare_public_source.py) | Copies allowlisted files, runs heuristic scans, and generates a manifest; target must not exist | Review all release contents, actual Git files, and history |
| [Provenance verifier](../scripts/verify_release_source.py) | Checks consistency of versions, licenses, manifest files, and provenance metadata | Actual correspondence with Git commits, historical build numbers, and signing-certificate comparison |
| [Deployment upgrade script](../deploy/scripts/release.sh) | Backs up, migrates, and upgrades the server API | Separate deployment task; do not run as a normal GitHub Release-creation step |

The current candidate workflow does not generate Windows/Linux server distributions. Before adding platforms, server managers, or other artifacts, confirm that source, build entry points, and acceptance requirements exist. Do not invent download items from plans.

## 3. Fix the version and source provenance

For every release, maintenance records should identify the target repository, previous version, current tag, full commit, client version, Android build number, artifact scope, and release type. A suggested record path is `output/release-<tag>/RELEASE_RECORD.md`; it is for maintenance and is not committed as source.

- Tags use `vMAJOR.MINOR.PATCH[-suffix]` and must equal `v` plus the `client/pubspec.yaml` version before `+buildNumber`. `preview`, `alpha`, `beta`, and `rc` versions use prerelease type unless explicitly arranged otherwise.
- Android build numbers must be positive integers and higher than the preceding version for same-package updates. The provenance script checks positivity only, not history.
- Root `LICENSE` and `client/LICENSE` must be byte-identical. Verify third-party authorization/notice requirements separately.
- Tags must reference a known full commit. Do not let release tools create tags from the default branch on demand or move published tags to pass checks.
- `SOURCE_COMMIT.txt`, `RELEASE_SOURCE.json`, notes, and maintenance records must use the same release commit. Do not present a local private-repository commit as a tag commit absent from the distribution repository.

For an existing distribution repository, generate snapshots from a clean checkout of the selected commit. On first export from a private workspace, review the allowlisted snapshot, create the distribution commit, then generate the final snapshot from that commit. Maintenance records may separately identify the original workspace commit, clearly distinguished from the release commit.

`verify_release_source.py --commit` accepts the caller's full Git object ID. Passing format checks does not prove that the commit matches the snapshot. Agents must compare the actually resolved tag commit and generate the snapshot from it, rather than merely supply an expected string.

Generate source archives before dependency downloads and signing configuration enter the snapshot. Build from that same snapshot and recheck with the workflow's `--expected-metadata` before/after building. `--allow-generated-files` allows only listed generated files, not changes to manifested source, licenses, or lockfiles.

Any changed distribution content requires a regenerated snapshot and manifest. Binary-affecting changes require rebuilding, signing, and verification. Do not pair new source archives with old APKs as one candidate. Editing remote Release notes alone does not require rebuilding binaries, but read back the notes and confirm unchanged attachments.

## 4. Run checks applicable to this scope

Use the [build guide](BUILDING.en.md) and workflows in the selected commit for commands and environment settings. Save execution date, commit, commands, tool versions, environment, and results; “all passed” alone is insufficient.

| Scope | Required recorded results | Limits of the result |
| --- | --- | --- |
| Source/scripts | Python checks, notice verification, allowlist scans, manifest, and actual Git-file review | `prepare_public_source.py --check` does not scan the entire directory/Git history or inspect image/JAR contents |
| Go server | Module verification, tests, vet, build, and actual execution of database integration tests | PostgreSQL tests skip without `PACTICK_TEST_DATABASE_URL` and cannot be recorded as passing; use isolated test databases only |
| Flutter client | Lockfile-enforced dependencies, analyze, tests, required builds | Debug APKs, widget tests, and screenshots do not replace final signed-APK device acceptance |
| Final APK | Package, version/build number, signature verification, certificate fingerprint, APK SHA-256, embedded licenses, actual runtime dependencies | `apksigner` success does not establish installation, update, background notification, or two-device sync behavior |
| Distribution review | Applicable scope, asset provenance, third-party terms, review records for final artifacts | Collector `completed_legal_audit: false` does not establish review completion; changing hashes does not resolve differences |
| Devices/deployment | Results under the [release process](RELEASING.en.md) and specialized checklists | LAN/debug, simulated scripts, or compilation cannot establish formal-package, public HTTPS/WSS, or real-server acceptance |
| Remote CI | Workflow link and final conclusion for the exact full commit | Queued, running, canceled, failed, and required-but-skipped jobs are not success |

Use the [Android task-reminder checklist](ANDROID_TASK_REMINDER_CHECKLIST.en.md) for current reminder changes. Device operations must stay within this task's Pactick authorization. Do not inspect other apps or files through ADB. The user handles system interfaces, unlocking, network, and permissions.

Formal signing must use the confirmed long-term key, comparing historical fingerprints and verifying the final APK. Do not substitute debug signatures for missing release configuration or uninstall the only data-bearing app to resolve update problems. See the [signing guide](ANDROID_SIGNING.en.md) and [release process](RELEASING.en.md) for configuration, backups, and certificate mismatches.

Preserve failed-check records, resolve causes, and rerun affected checks. If an environment is unavailable or execution prohibited, record Not run and the reason. Prerelease labeling does not waive acceptance automatically. If the user explicitly accepts preview distribution with incomplete checks, record its authorized scope and gaps without marking them passed. Without that acceptance, local candidates or authorized drafts may still be delivered.

## 5. Organize attachments and generate checksums

Source repositories hold source, scripts, tests, and public documents. APKs, AABs, executables, installers, and build archives are Release assets, not source commits. Reviewed build-dependency exceptions follow the existing allowlist, such as the Gradle wrapper JAR.

Select only standard artifacts matching this release's requirements. A file generated by a workflow is not automatically a Release attachment.

| Standard attachment | Applicability and requirements |
| --- | --- |
| Source archive | Reviewed allowlisted source; keep `SOURCE_MANIFEST.json` inside, matching provenance metadata; do not upload it separately by default |
| APK | For Android distribution; must be the exact final verified file. The workflow outputs `pactick.apk`, which may be renamed before upload to include version/build number |
| Other-platform installer/executable package | Only when this task explicitly includes that platform and source/build/acceptance requirements exist. Do not add unrequested platforms or tools |
| `SHA256SUMS.txt` | Covers every other final uploaded asset using final filenames; excludes itself |

Raw JSON supports tools and does not replace user-readable release notes. By default, do not paste raw JSON, JSON code blocks, or API responses into Release bodies or upload `.json`, `.jsonl`, and similar machine records as standalone assets. This includes `RELEASE_SOURCE.json`, `SOURCE_MANIFEST.json`, `THIRD_PARTY_NOTICES.json`, `FLUTTER_TOOLCHAIN.json`, `DISTRIBUTION_REVIEW.json`, and similar files. An exception requires the user's explicit instruction that a particular JSON file or verbatim content must be included in this Release.

Project-required JSON configuration/metadata and generated `SOURCE_MANIFEST.json` retain their existing structure inside source archives and are not separate downloads. Do not evade these rules by renaming, converting, repackaging, or inserting extra internal JSON, reports, or logs into source archives.

The following materials must still be generated and verified under the existing process but are for maintenance/candidate review by default, not direct Release publication:

| Maintenance material | Storage and use |
| --- | --- |
| `SOURCE_COMMIT.txt`, `RELEASE_SOURCE.json` | Full commit, tag, version/build, and provenance hashes; Release bodies include only necessary provenance fields |
| `APK_SIGNING_CERTIFICATE.txt` | Full signature-verification output; Release bodies include necessary conclusions such as certificate SHA-256 |
| Toolchain/runtime dependency records | Actual tool versions, dependency inventories, captured results for provenance/build rechecking |
| Distribution reviews, validation reports, detailed logs | Review basis and evidence; section 6 allows only concise verified facts, limits, and known issues in the body, not full reports |

Provide required third-party notices, license texts, and NOTICE with source archives/installers according to distribution obligations. Standalone notice JSON or internal review reports do not replace those obligations. If the authorized attachment scope cannot meet license requirements, explain the gap and await an explicit scope decision; do not add assets or remove required notices independently.

After packaging, inspect archives and exclude keystores, `key.properties`, real environment configuration, databases, backups, tokens, private deployment information, and test logs. GitHub-generated Source code links do not replace reviewed source archives and manifests.

The attachment inventory must record local location, final filename, purpose, byte size, SHA-256, and inclusion basis for each item. Inclusion basis must be a standard attachment and its applicable condition from this section or an explicit request for that item. “Convenient for auditing,” “generated by tooling,” or other agent-selected reasons are insufficient. Keep this inventory in maintenance records; it is not automatically an attachment.

After renaming, update the inventory and `SHA256SUMS.txt`. Recompressing, signing, or changing contents requires new hashes. Checksums do not establish publisher identity or distribution authorization.

Do not upload wildcards over the entire workspace, `output/`, or Actions artifact directory. Select files from an explicit inventory first. Attachment counts follow the current scope, not historical totals.

## 6. Write user-facing Release notes

Use readable Chinese paragraphs, lists, or tables to explain changes, which files to download, installation/update steps, and unverified conditions. Every functionality/validation claim must match this source and final artifacts. Standard body scope is limited to the following; other subjects require explicit user requests for this Release.

- State version, release type, primary changes, and user-affecting fixes. Do not present planned functions as available.
- Explain Android package name, minimum system requirements, and same-package signature/build-number rules. Link instructions for renaming or migration.
- List actual platforms, architectures, attachment purposes, and required runtime dependencies. Do not describe nonexistent installers or GUIs.
- Retain known issues, unverified scenarios, migration restrictions, and user-affecting faults. Distinguish build, signing, and device results.
- Provide final APK SHA-256, certificate SHA-256, and checksum-file access. Explain that the client opens the release page externally and does not automatically verify APK integrity/certificates.
- Preserve current local-first, optional-sync behavior in descriptions. A source preview or server download does not imply recommended public deployment.
- Link getting started, licensing, third-party notices, issue reporting, and private security reporting. Do not expose private paths, addresses, credentials, or internal logs.

Public notes omit agent operations, build retries, internal antivirus alerts, and troubleshooting details irrelevant to user decisions. If a problem affects attachment availability, integrity, or safety, fix it and describe its impact/disposition; deleting internal records does not replace remediation.

When using results from internal JSON/logs, extract only conclusions within standard scope and rewrite them readably. Do not expand the Release with raw data, full test inventories, internal review reports, or long item-by-item prose conversions.

Adapt the following structure to scope and remove placeholders before publication:

```markdown
# Pactick <version> (prerelease or stable)

## Changes

- <Functions/fixes actually provided>

## Downloads and installation

| File | Platform or purpose | Installation, upgrade, or runtime requirements |
| --- | --- | --- |
| <Actual attachment> | <Platform and architecture> | <Prerequisites and instructions> |

## Verified matters and limitations

- <Checks completed for these artifacts>
- <Unverified scenarios, known issues, migration limits>

## Source and verification

- Source tag: <tag>; full commit: <commit>
- APK SHA-256: <final hash; remove without APK>
- Signing certificate SHA-256: <final fingerprint; remove without APK>
- Checksums, licensing, feedback: <corresponding assets/document links>
```

## 7. Create drafts, upload, and publish

Run this section only when remote actions are authorized. First prepare reviewable local candidates, notes, and an attachment inventory, checking inclusion basis for every body topic and attachment. Remove anything outside standard scope without explicit user request, including raw JSON, from pending publication; retain internal verification materials.

1. Reread the remote repository, same-name tag, and Release. Check the tag's actual full commit; `target_commitish` does not replace resolving the tag.
2. Push required source and explicit tags within authorization and verify remote results. Do not substitute `git push --mirror`, force pushes, or bulk unrelated-tag pushes.
3. If no same-name Release exists, first create a draft with explicit repository, tag, prerelease state, and Latest setting. If it exists, continue using its ID and actual state. Do not overwrite a draft outside this task.
4. Upload only inventoried items. Read back each asset's name, size, upload state, and SHA-256, and ensure the remote set exactly matches the inventory. Compare `digest` when provided; otherwise download into a new directory and hash. Upload-command success is not completed verification.
5. Compare read-back title/body/state to local notes. Confirm that topics/assets are standard or specifically requested; raw JSON requires an item-specific request. Confirm uploaded material matches the validated candidate. With full publication authorization and satisfied conditions, publish directly. With draft-only authorization, retain and deliver the draft.
6. After publishing, reread Release ID, page, tag commit, `draft`, `prerelease`, Latest, and attachment inventory to confirm the agreed state. Redownload deliverables through the release entry and compare SHA-256 with the local inventory. Use authorized identity for private repositories and report access limits.

With GitHub CLI, specify `--repo`. Use `--verify-tag` for existing remote tags so missing tags are not automatically created from the default branch. Write notes to a UTF-8 file and pass `--notes-file`. Use `--draft` for drafts, `--prerelease` for prereleases, and explicit `--latest=false` for previews. See [gh release create](https://cli.github.com/manual/gh_release_create).

Publishing an existing draft changes visibility. Run `gh release edit <tag> --draft=false --repo <owner/repo>` only with publication authorization, and explicitly verify other states. See [gh release edit](https://cli.github.com/manual/gh_release_edit) and the [Release assets API](https://docs.github.com/en/rest/releases/assets) for `size`, `state`, and `digest`.

When user approval or repository-environment review is required, keep the candidate reviewable and identify the exact state change approval permits. Do not bypass environment protection or repeatedly request already granted authorization for identical steps.

## 8. Failures, retries, and published-content corrections

| Situation | Agent requirement |
| --- | --- |
| Local build/verification fails | Retain cause, fix, and rerun affected checks; never publish failed candidates |
| Authentication, permission, or environment approval blocked | Retain local candidate/actual remote state, explain blocked action; do not disable protection or expand privileges |
| Network timeout, TLS failure, interrupted upload | Query whether the action already succeeded before retrying; do not blindly recreate Releases, tags, or same-name assets |
| Same-name draft asset exists | Reuse if hashes match. Otherwise verify authorized update scope, update, then recheck the full inventory/checksums |
| Publication request errors but remote state is published | Verify/report the published state; do not create a second Release. Handle further issues as published corrections |
| Incorrect published asset | Report impact and propose withdrawal/new version. Without explicit authorization, do not delete Releases, move tags, or replace published assets |
| Notes-only correction | Update within authorization, read back, and confirm unchanged tags/state/assets |
| Unrequested raw JSON, extra reports, or other nonstandard items found in draft/published content | Stop further upload/publication and record items. Remove agent-added items in this task's draft when current authorization allows. Existing/published items require corresponding modification authorization and are not automatically allowed to remain |
| Interrupted or incomplete task | Record Release ID, current state, completed uploads, missing items, and continuation requirements. Do not report publication complete |

Cleanup applies only to confirmed temporary paths created for this task. Do not delete long-term signing keys, unique backups, unpublished work, or server data. Database upgrades/rollbacks are separate deployments; see [self-hosting](SELF_HOSTING.en.md).

## 9. Delivery and completion conditions

The final response must match the actual stopping point and include at least:

- Local candidate location or Release link, and remote draft/prerelease/repository visibility states.
- Tag, full commit, client version, and Android build number; explain inapplicable fields.
- Delivered platforms/assets and checksum location; for APKs, certificate fingerprint or its record location.
- Executed checks, failed/not-run checks, remaining acceptance, and remote CI commit/results.
- Whether upload, publication, and redownload verification completed; identify gaps and next steps if incomplete.
- Whether body/assets comply with this specification; list specifically requested extras and their authorizing instructions.

Drafting notes does not create a remote draft. Uploading Actions artifacts does not publish a Release. Publishing a Release does not establish device or deployment acceptance. Report the corresponding Release task complete only after the agreed final state, provenance correspondence, asset verification, content-scope checks, and note read-back are complete. These requirements are enforced through project instructions and pre/post-release verification, not a claim that current scripts automate every extra-item restriction.
