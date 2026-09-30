// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GifSnap",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "GifSnap", targets: ["GifSnap"]),
        .library(name: "GifSnapUI", targets: ["GifSnapUI"])
    ],
    dependencies: [.package(url: "https://github.com/SDWebImage/SDWebImage.git", exact: "5.21.7")],
    targets: [
        .target(name: "GifSnap"),
        .target(name: "GifSnapUI", dependencies: ["GifSnap", .product(name: "SDWebImage", package: "SDWebImage", condition: .when(platforms: [.iOS]))]),
        .testTarget(name: "GifSnapTests", dependencies: ["GifSnap"]),
        .testTarget(name: "GifSnapUITests", dependencies: ["GifSnapUI", "GifSnap", .product(name: "SDWebImage", package: "SDWebImage", condition: .when(platforms: [.iOS]))], resources: [.copy("Fixtures")])
    ]
)
