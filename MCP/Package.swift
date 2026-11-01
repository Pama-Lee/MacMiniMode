// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacMiniModeMCP",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "macminimode-mcp", targets: ["MacMiniModeMCP"])],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
                   .package(url: "https://github.com/apple/swift-log.git", exact: "1.16.2")],
    targets: [.executableTarget(name: "MacMiniModeMCP", dependencies: [.product(name: "MCP", package: "swift-sdk"), .product(name: "Logging", package: "swift-log")]),
              .testTarget(name: "MacMiniModeMCPTests", dependencies: ["MacMiniModeMCP"])]
)
