// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "Kineo",
    platforms: [.macOS(.v10_15)],
	products: [
		.library(name: "Kineo", targets: ["Kineo"]),
	],    
    dependencies: [
		.package(name: "SPARQLSyntax", url: "https://github.com/kasei/swift-sparql-syntax.git", .upToNextMinor(from: "0.0.97")),
		.package(name: "serd", url: "https://github.com/kasei/swift-serd.git", .upToNextMinor(from: "0.0.3")),
		.package(name: "CryptoSwift", url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMinor(from: "1.0.0")),
		.package(url: "https://github.com/kasei/URITemplate.git", .upToNextMinor(from: "2.0.10")),
		.package(name: "SQLite.swift", url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.11.5")),
		.package(name: "Diomede", url: "https://github.com/kasei/diomede.git", .upToNextMinor(from: "0.0.2")),
    ],
    targets: [
    	.target(
    		name: "Kineo",
			dependencies: [
				"CryptoSwift",
				"SPARQLSyntax",
				"URITemplate",
				"serd",
				.product(name: "SQLite", package: "SQLite.swift"),
				.product(name: "DiomedeQuadStore", package: "Diomede"),
			]
    	),
        .target(
            name: "kineo-cli",
            dependencies: ["Kineo", "SPARQLSyntax"]
        ),
        .target(
            name: "kineo-client",
            dependencies: ["Kineo", "SPARQLSyntax"]
        ),
        .target(
            name: "kineo-dawg-test",
            dependencies: ["Kineo", "SPARQLSyntax"]
        ),
        .target(
            name: "kineo-parse",
            dependencies: ["Kineo", "SPARQLSyntax"]
        ),
        .target(
            name: "kineo-test",
            dependencies: ["Kineo", "SPARQLSyntax"]
        ),
        .testTarget(name: "KineoTests", dependencies: ["Kineo"])
    ]
)
