import Foundation

// Stub so a fresh clone compiles. An empty DSN leaves crash reporting off.
// CI (ci_scripts/ci_post_clone.sh) overwrites this file with the real DSN
// before every shipped build, and fails the build when it has none.
let analyticsDSN = ""
