/// Single source of truth for the currently-running app version.
///
/// Kept as compile-time constants so the update checker, the About section
/// and the Audit trail all agree on one pair of numbers. Bump these
/// alongside [pubspec.yaml] `version:` on every release tag — the update
/// checker compares [appBuildNumber] against the manifest to decide
/// whether a new build is available.
library;

/// Human-readable version string. Shown in Settings → About.
const String appVersionName = '1.3.0';

/// Monotonic build number. Compared against [UpdateManifest.buildNumber].
const int appBuildNumber = 130;
