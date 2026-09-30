# Music Beat Companion

An experimental, independent iOS 16.1+ app for beat-timed haptics alongside
the unmodified system Music app. Bundle ID: `com.facrese.musicbeatcompanion`.
The source and GitHub release contain no Apple Music binary, credentials, or
tokens.

The app reads the system music player's now-playing item and playback position
through `MPMusicPlayerController.systemMusicPlayer`. It obtains authorization
headers only from Apple Music's own requests made in its embedded WebKit view
after the user signs in there; it never writes those headers to disk or logs.
It uses the undocumented catalog `audio-analysis` relationship to obtain
`beatsInMilliseconds` and `barsInMilliseconds`, caches successful maps by
catalog song ID, and schedules Core Haptics transients with bar accents.

## First test

1. Install the IPA from the `companion-test` release in TrollStore. Do not
   uninstall or replace Apple's Music app.
2. Open the companion, tap **Включить хаптик**, and allow music-library access.
3. Tap **Войти через Apple Music Web**, sign in if asked, and let the song page
   finish loading. Return to the companion when it shows web authorization.
4. Start a catalog song in the original Music app. Check the companion for a
   catalog ID, beat count, and haptic status.

This first build is not yet validated on the target iPhone. Apple may refuse
sign-in in an embedded web view or change the private analysis endpoint. The
background-audio keepalive is experimental: Core Haptics can stop when iOS
suspends the companion. No claim is made that this reproduces Apple's AHAP
Music Haptics assets.
