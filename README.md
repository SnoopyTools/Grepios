# grepios — grep for iOS

A SwiftUI GUI for grep. Search the contents of files and folders on your iPhone with regular expressions.

## Features
- Regex search (NSRegularExpression / ICU syntax) with match highlighting
- Quick flag chips: `-i` ignore case, `-F` literal, `-w` whole word, `-v` invert, `-r` recursive
- Context lines (`-C`), max matches per file (`-m`), include/exclude globs, skip binary files, hidden files, size limit
- Search the app's Documents folder (visible in Files ▸ On My iPhone ▸ grepios) or any folder/file picked from the Files app (remembered between launches)
- Results streamed live, grouped by file; tap a line to open the file scrolled to it
- Long-press a line to copy it / copy as `path:line:text`; share all results as grep-style text

## Build
Push to GitHub; the Actions workflow installs XcodeGen, builds an unsigned IPA and uploads it as the `grepios-ipa` artifact. Sideload with LiveContainer, AltStore, etc.

Locally: `brew install xcodegen && xcodegen generate && open grepios.xcodeproj`.
