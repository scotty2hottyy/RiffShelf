# iCloud Drive import (release candidate)

The default file source is the user's `iCloud Drive/RiffShelf` document folder.
On iOS, RiffShelf requests its app-specific iCloud Documents container and
publishes its `Documents` directory in Files. Supported files are `.txt`,
`.gp3`, `.gp4`, `.gp5`, and `.gpx` (case insensitive).

- Auto-scan when Library first mounts and the app returns to foreground.
- The user may tap **Sync now** to retry downloads or rescan.
- Each playable track of a Guitar Pro document is imported separately.
- Existing content-and-track hashes prevent duplicates; originals stay in iCloud.
- SQLite and artwork remain local for offline reading; iCloud is not required
  to open previously saved tabs.
- iCloud is unavailable on Android; manual import still works.
- iOS may postpone fetching cloud-only files; rescan after download.
- This does NOT create background jobs while the app is terminated, and does
  NOT yet support the proposed `.riffshelf` multi-arrangement container.

## Required Apple setup before physical-device testing

1. In Apple Developer, enable iCloud Documents for the existing app identifier
   `com.sonniersolution.riffshelf`; create/enable container
   `iCloud.com.sonniersolution.riffshelf` and authorize the app to use it.
2. Regenerate/download signing profiles if required. Preserve the working local
   team's signing settings, and verify entitlements in the signed binary.
3. Build/install on an iPhone with iCloud Drive enabled, then put a valid
   `.txt` or `.gp5` file in Files > iCloud Drive > RiffShelf.
4. Open Library, tap Sync now if needed; verify offline access and duplicate
   prevention after relaunch. Repeat with a Mac-originated file.

No server, paid subscription, or provider login is added here. Songsterr and
Ultimate Guitar account integrations require a supported, authorized sign-in/API
before they can be offered as native account connections. Existing Discover
search is deliberately unchanged on this release branch.

The iOS signing capability and live sync require a real-device verification.
