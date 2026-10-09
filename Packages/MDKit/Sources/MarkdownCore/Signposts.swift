import os

/// `os_signpost` intervals for Instruments and `make perf`: parse, render, export.
public enum Signposts {
    public static let signposter = OSSignposter(subsystem: "com.kemalmaulana.mdsyndrome", category: "perf")
}
