// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Repo: https://github.com/johnno1962/HotReloading
//  $Id: //depot/HotReloading/Package.swift#202 $
//

import PackageDescription
import Foundation

// This means of locating the IP address of developer's
// Mac has been replaced by a multicast implementation.
// If the multicast implementation fails to connect,
// clone the HotReloading project and hardcode the IP
// address of your Mac into the hostname value below.
// Then drag the clone onto your project to have it
// take precedence over the configured version.
var hostname = Host.current().name ?? "localhost"
// hostname = "192.168.0.243" // for example

let package = Package(
    name: "HotReloading",
    platforms: [.macOS("10.12"), .iOS("13.0"), .tvOS("10.0")],
    products: [
        .library(name: "HotReloading", targets: ["HotReloading"]),
    ],
    dependencies: [
        .package(name:"SwiftTrace",  path: "./SubPackages/SwiftTrace"),
        .package(name:"SwiftRegex5", path: "./SubPackages/SwiftRegex5"),
    ],
    targets: [
        .target(name: "HotReloading", dependencies: ["HotReloadingGuts",
                                                     .product(name: "SwiftTraceD", package: "SwiftTrace"),
                                                     .product(name: "SwiftRegex", package: "SwiftRegex5")]),
        .target(name: "HotReloadingGuts",
                cSettings: [.define("DEVELOPER_HOST", to: "\"\(hostname)\"")])
    ],
    cxxLanguageStandard: .cxx11
)
