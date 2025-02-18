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
        // .library(name: "HotReloadingGuts", targets: ["HotReloadingGuts"]),
        // .library(name: "injectiondGuts", targets: ["injectiondGuts"]),
        // .executable(name: "injectiond", targets: ["injectiond"]),
    ],
    dependencies: [
        .package(name:"SwiftTrace",  path: "Checkouts/SwiftTrace"),
        .package(name:"SwiftRegex5", path: "Checkouts/SwiftRegex5"),
//        .package(path: "Checkouts/XprobePlugin"),
//        .package(path: "Checkouts/Remote"),
        //        .package(path: "Checkouts/ProfileSwiftUI"),
//        .package(path: "Checkouts/HotSwiftUI"),
        //        .package(url: "https://github.com/johnno1962/DLKit",
        //                 .upToNextMinor(from: "1.2.1")),
        //        .package(url: "https://github.com/johnno1962/InjectionScratch",
        //                 .upToNextMinor(from: "1.2.12")),
    ],
    targets: [
        .target(name: "HotReloading", dependencies: ["HotReloadingGuts",
                                                     .product(name: "SwiftTraceD", package: "SwiftTrace"),
//                                                     .product(name: "Xprobe", package: "XprobePlugin"),
                                                     .product(name: "SwiftRegex", package: "SwiftRegex5")]),
        .target(name: "HotReloadingGuts",
                cSettings: [.define("DEVELOPER_HOST", to: "\"\(hostname)\"")]),
        .target(name: "injectiondGuts"),
        .target(name: "injectiond", dependencies: ["HotReloadingGuts", "injectiondGuts",
                                                   .product(name: "SwiftRegex", package: "SwiftRegex5"),
//                                                   .product(name: "XprobeUI", package: "XprobePlugin")
        ],
                swiftSettings: [.define("INJECTION_III_APP")])],
    cxxLanguageStandard: .cxx11
)
