// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TLGLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TLGLauncherCore"),
        .executableTarget(
            name: "TLGLauncher",
            dependencies: ["TLGLauncherCore"]
        ),
        // Test-library-free check runner: the machine builds with Command Line
        // Tools only, which ship neither XCTest nor Swift Testing. `swift run
        // tlg-checks` runs the whole suite and exits non-zero on failure.
        .executableTarget(
            name: "TLGLauncherChecks",
            dependencies: ["TLGLauncherCore"]
        ),
        // CLI for generating the guide's game data from an installed build,
        // used for scripted verification against the remote pipeline.
        .executableTarget(
            name: "GuideDataTool",
            dependencies: ["TLGLauncherCore"]
        ),
    ]
)
