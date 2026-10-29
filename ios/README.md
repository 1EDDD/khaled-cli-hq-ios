## khaled_cli HQ for iPhone and iPad

This is a native iOS/iPadOS port of the video-processing workflow from the macOS project. The app uses Photos and Files to select a video, re-encodes locally to H.264 with AVFoundation, applies a native Swift MP4 sample-table transformation, then opens the result for sharing or saving.

## Requirements

- iOS/iPadOS 17 or newer
- Xcode 16 or newer
- A real device is recommended for video encoding validation

## Build in Xcode

1. Open KhaledHQ.xcodeproj.
2. Select the KhaledHQ scheme and an iPhone or iPad destination.
3. Set your own development Team and signing identity in Xcode.
4. Build and run.

## Build with GitHub Actions

The workflow at .github/workflows/ios-build.yml builds the app for iOS and uploads KhaledHQ-unsigned.ipa as an artifact. The IPA is UNSIGNED; it must be signed with your own Apple development certificate/profile or a sideloading workflow before installation. It cannot be installed directly as-is.

## Processing notes

- Original source files are not modified. Outputs are saved in the app's Documents/Khaled HQ folder and can be shared from the app.
- The MP4 transformation currently requires a conventional MP4 with one mdat box and a constant-frame-rate video sample table. Unsupported layouts are rejected rather than reported as successful.
- This technique manipulates container metadata and includes filler samples, so some desktop players can show warnings while decoding the synthetic frames. The app checks the MP4 structure and confirms the original video track/duration remain present, but it cannot guarantee that TikTok will honor original quality. TikTok controls its own upload transcoding and may change behavior at any time.
- No upload to a third-party server is part of this app's processing path.
