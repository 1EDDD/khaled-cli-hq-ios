# iOS / iPadOS port

A native SwiftUI app is available in the ios/ directory. It uses PhotosPicker and the Files importer, AVFoundation for on-device H.264 export, and a Swift MP4 sample-table transformation to replace the original macOS-only shell/Python path. The app target is iOS/iPadOS 17+.

See ios/README.md for Xcode build and signing instructions.

**Important:** the output technique alters MP4 sample tables and appends filler samples. It preserves the original encoded video samples and duration, but it is a heuristic for TikTok's upload handling, not a guarantee against platform transcoding. Some desktop decoders may log warnings around the synthetic samples. Unsupported or variable-rate MP4 layouts are rejected.
