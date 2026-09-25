// swift-tools-version:5.9
// Core poker engine, strategy and grading. The iOS app compiles these same
// sources directly (see GTOTrainer.xcodeproj); this package exists so the
// engine can be built and unit-tested on any machine with `swift test`.
import PackageDescription

let package = Package(
    name: "TrainerCore",
    products: [.library(name: "TrainerCore", targets: ["TrainerCore"])],
    targets: [
        .target(name: "TrainerCore"),
        .testTarget(name: "TrainerCoreTests", dependencies: ["TrainerCore"]),
    ]
)
