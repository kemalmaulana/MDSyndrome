# MDSyndrome

A native, Apple-Silicon Markdown editor and reader for macOS. It replaces
[MacDown](https://macdown.uranusjr.com), whose Intel-only build runs under Rosetta 2.

- Native SwiftUI preview (no web view) and an AppKit text editor
- CommonMark + GitHub Flavored Markdown via cmark-gfm
- Spec: [`docs/superpowers/specs/2026-10-04-mdsyndrome-prd.md`](docs/superpowers/specs/2026-10-04-mdsyndrome-prd.md)

## Requirements

- macOS 26 or later, Apple Silicon recommended
- Xcode 27
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and run

```bash
make run        # generate the Xcode project, build, launch
make test       # lint + package tests + app unit tests
make test-ui    # UI tests (drive the real app for about a minute)
make gen        # regenerate MDSyndrome.xcodeproj after pulling
```

`MDSyndrome.xcodeproj` is generated from `project.yml` and not committed.

## License

MIT, see [LICENSE](LICENSE). Third-party notices are in [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).
