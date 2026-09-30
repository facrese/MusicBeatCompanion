# Music Beat Companion

An experimental, independent iOS 16.1+ app for beat-timed haptics alongside
the unmodified system Music app. Bundle ID: `com.facrese.musicbeatcompanion`.
The source and GitHub release contain no Apple Music binary, credentials, or
tokens.

The app reads the system music player's now-playing item and playback position
through `MPMusicPlayerController.systemMusicPlayer`. It obtains authorization
headers only from Apple Music's own requests made in its embedded WebKit view
after the user signs in there. The headers are stored in this app's iOS Keychain
and never included in the IPA or logs. A tiny WebKit view refreshes the session
automatically when the companion starts or returns to the foreground.
It uses the undocumented catalog `audio-analysis` relationship to obtain
`beatsInMilliseconds` and `barsInMilliseconds`, caches successful maps by
catalog song ID, and schedules Core Haptics transients with bar accents.
Beat and bar layers have independent intensity and sharpness controls, both
persisted across launches. Sharpness changes the tactile feel (soft to crisp);
it does **not** expose a physical frequency in hertz. A -500 to +500 ms timing
offset compensates for device-specific latency; positive values play earlier.

## First test

1. Install the IPA from the `companion-test` release in TrollStore. Do not
   uninstall or replace Apple's Music app.
2. Open the companion, tap **Включить хаптик**, and allow music-library access.
3. Tap **Войти через Apple Music Web** once, sign in if asked, and let the song
   page finish loading. Future launches reuse Keychain and WebKit cookies.
4. Start a catalog song in the original Music app. Check the companion for a
   catalog ID, beat count, and haptic status.

Version 0.1 was confirmed working in the foreground on an iPhone XR, but not in
the background. Version 0.2 uses a near-inaudible audio stream with
`mixWithOthers` to try to keep the companion active while Music plays and shows
the latest background/engine diagnostic on screen. This is experimental: iOS
can still suspend Core Haptics. The private analysis endpoint can change. No
claim is made that this reproduces Apple's AHAP Music Haptics assets.
