# The move to one.floo.maagical

Decided 2026-11-20. Until 1.5 the app ran as `one.floo.vibeflow` (Dev: `one.floo.vibeflow.dev`),
kept on purpose when VibeFlow became Maagical (#50), because Sparkle, TCC and the Keychain key
on it. With only a handful of installs, the author chose to move now rather than ship the old
name to every future install: from 1.6 the app is `one.floo.maagical` (Dev:
`one.floo.maagical.dev`), and nothing on a fresh install says VibeFlow.

## What changes

| | until 1.5 | from 1.6 |
|---|---|---|
| Bundle id | one.floo.vibeflow(.dev) | one.floo.maagical(.dev) |
| Settings | ~/Library/Preferences/one.floo.vibeflow.plist | one.floo.maagical.plist |
| Data | Application Support/VibeFlow | Application Support/Maagical |
| Caches | Caches/VibeFlow | Caches/Maagical |
| API keys | Keychain service one.floo.vibeflow | one.floo.maagical |
| Google sign-in | one.floo.vibeflow(.dev).google | one.floo.maagical(.dev).google |
| Log subsystem | one.floo.vibeflow | one.floo.maagical |
| Update feed | releases/latest/download/appcast.xml | maagical-appcast.xml |
| Nightly feed | releases/download/nightly/appcast.xml | maagical-appcast.xml |

`AppIdentity` (MaagicalCore) picks the folder and Keychain names from the running bundle id, so
a build under the old id (the bridge) still finds its own data and keys.

Unchanged on purpose: the Sparkle signing key and the Sentry token stay under Keychain account
`vibeflow`, the `VibeFlowNotary` profile, `VF_*` build settings, `vf-eval` and the shared
Swift package cache in Caches/VibeFlow/SourcePackages. They live only on the author's Mac, never
on an install.

## Why a bridge

Sparkle refuses an update whose bundle id differs from the installed app ("Failed to match host
bundle identifiers"), so an old copy can never update straight to 1.6. Every old copy reads
`appcast.xml`; that feed now offers the **bridge**: the same 1.6 build, signed under the old id.
Sparkle installs it like any update. The bridge (BridgeMove) then:

1. asks at launch ("Maagical has a new home", Update Now / Later), and keeps a card in the menu
   bar panel until it moves;
2. downloads the newest release's Maagical.dmg and checks it like Back to Stable does
   (StableInstaller: Developer ID, team X7UXDLS9F7, notarized, bundle id one.floo.maagical);
3. puts it in place as Maagical.app next to itself (a 1.5 release sits at VibeFlow.app) and moves
   the old app to the Trash;
4. copies the API keys and the Google sign-in to the new Keychain services with an access list
   that names the new app, so the new app reads them without a Keychain prompt (the old items
   belong to the old app, and a different bundle id would get one prompt per item);
5. unregisters its own login item and opens the new app, then quits.

The new app's first launch (LegacyMigration) imports settings from the old preferences domain,
including the menu bar positions (the icon's autosave name changes from `vibeflow-icon` to
`maagical-icon`), copies any keys the bridge did not hand over (a copy installed by hand gets
the Keychain prompts), copies Application Support/VibeFlow to Application Support/Maagical
(an APFS clone) and registers Open at Login again when it was on. The old folder, preferences
and Keychain items stay for now: the author's Mac still runs old Dev builds next to new ones.
A later release can delete them.

What cannot move: Accessibility, Microphone, Calendar and notification permissions belong to the
bundle id. The new app asks for them like a fresh install.

## Releases

- `scripts/release.sh --publish`: when the previous release's `appcast.xml` does not point at a
  bridge (true for v1.5.0), it builds the bridge too (`PRODUCT_BUNDLE_IDENTIFIER=one.floo.vibeflow`,
  `VF_FEED_URL` = the old feed), uploads `Maagical-bridge.dmg`, `appcast.xml` for it and
  `VibeFlow.dmg` (the bridge again, for Back to Stable in the 1.5 nightlies), and puts the same
  `appcast.xml` on the nightly release for nightlies under the old id. Later releases download
  that `appcast.xml` from the release before and upload it again, so
  `.../latest/download/appcast.xml` always offers the bridge.
- The bridge has the release's version and build number, above every old release and nightly.
- Nightlies publish `maagical-appcast.xml` only; `appcast.xml` on the nightly stays on the bridge.
- `scripts/release.sh --bridge` builds both locally without publishing.

## Testing before the release

On a second Mac or user account with 1.5 installed:

1. `scripts/release.sh --bridge` (notarizes both; nothing is published).
2. Install `build/release/Maagical-bridge.dmg` over 1.5 (as Sparkle would), and point it at the new
   DMG: `defaults write one.floo.vibeflow update.releaseDMG file:///path/to/Maagical-<version>.dmg`.
3. Open it, press Update Now. Check: no Keychain prompt, settings, history and menu bar
   position kept, VibeFlow.app in the Trash, Maagical.app in Applications, Open at Login on
   again, permissions asked once. The test URL stays behind (LegacyImport skips it).
