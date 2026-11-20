# Device regression checklist

Run this on at least one physical Android phone and one iPhone before a demo or release. Automated tests cannot cover the microphone, the system file picker, or live search, so this pass covers them by hand.

Copy the table into the release issue and fill in the result for each device.

**Build:** `________` · **Android device / OS:** `________` · **iOS device / OS:** `________` · **Tester:** `________` · **Date:** `________`

## Setup

- Install a fresh build (uninstall any earlier version first) so first-run behavior is tested.
- Have a Guitar Pro file (GP5 works) and a plain-text tab saved on the device or in cloud storage the file picker can reach.
- Have a guitar or bass nearby for the tuner and note-by-note checks. A tuner app or online tone generator also works.

## Checklist

| # | Area | Steps | Expected | Android | iOS |
|---|---|---|---|---|---|
| 1 | Launch | Open the app for the first time | Opens on Discover in dark theme with five tabs in the bottom bar | | |
| 2 | Navigation | Visit every tab, then return to Discover | Each tab opens; Discover keeps the text you typed | | |
| 3 | Restore | Pick the Library tab, close the app from the app switcher, reopen | App reopens on Library | | |
| 4 | Search | Discover: search "Come As You Are" | Results list guitar and bass versions | | |
| 5 | Search filter | Set the instrument filter to Bass and search again | Only bass results | | |
| 6 | Search offline | Turn on airplane mode and search | An error with **Retry** is shown; no crash | | |
| 7 | Save from search | Back online, open a result, choose an arrangement, tap **Save** | The Save button shows the tab as saved, and it appears in Library | | |
| 8 | Duplicate save | Save the same arrangement again | Message that it is already in your library | | |
| 9 | Import GP | Library: **Import Tab**, pick a Guitar Pro file, choose a track | "Tab imported"; tab appears with the right title and string count | | |
| 10 | Import text | Import a `.txt` tab | Tab appears; opening it shows the ASCII view | | |
| 11 | Import invalid | Import a file that is not a tab (for example a PDF renamed to `.txt`) | Clear error message; nothing added | | |
| 12 | Library filters | Search by title, filter by instrument, filter favorites, filter by tag | List updates correctly for each filter | | |
| 13 | Edit and favorite | Edit a tab's title and tags; favorite it | Changes persist after restarting the app | | |
| 14 | Delete | Delete a tab and confirm | Tab is removed and stays removed after restart | | |
| 15 | Artwork | Open a saved song with a well-known album | Cover loads or can be chosen with the album picker; still shown offline | | |
| 16 | Tab viewer | Open a structured tab; switch between **Structured** and **ASCII** | Both views render and scroll | | |
| 17 | Practice prep | Practice: open a tab | "Get ready to practice" shows instrument, strings, and tuning | | |
| 18 | Timed scrolling | Start practice in **Timed scrolling** and press Play | Notes scroll right to left at the tab's tempo | | |
| 19 | Speed and loop | Change speed; select a section and enable looping | Playback speed changes; the section repeats | | |
| 20 | Note by note | Switch to **Note by note**, press Play, play the expected notes | Each correct note advances; wrong notes do not | | |
| 21 | Mic permission | First time the microphone is used | System permission prompt appears; denying shows a message, not a crash | | |
| 22 | Save session | Tap **Save results**, mark the section complete, **Save** | "Practice session saved locally." | | |
| 23 | History | Practice → **Practice history** | The session appears with the right duration; totals update; clearing history empties it after confirmation | | |
| 24 | Tuner | Tuner: **Start tuning**, play each open string | Correct note detected; needle centers within about 5 cents when in tune | | |
| 25 | Tuner presets | Switch to bass, then a drop tuning, then create a custom tuning | Target notes change; custom tuning persists after restart | | |
| 26 | Tuner release | Start the tuner, then switch to another tab | Microphone indicator turns off | | |
| 27 | Theme | Settings: turn on **Light Mode**, restart the app | Light theme is kept after restart | | |
| 28 | Small screen | Repeat 1 to 2 on the smallest available device or with large system text | No overflow stripes or clipped buttons | | |
| 29 | Background | Start practice, lock the phone for 30 seconds, unlock | App resumes without a crash | | |

## Reporting failures

For each failure, open an issue that includes the checklist number, device and OS version, steps to reproduce, and a screenshot or screen recording. Link it to the release milestone and to #43 if it is a UI issue.
