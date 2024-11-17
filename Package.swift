// swift-tools-version:5.7
import PackageDescription

let package = Package(
	name: "Kineo",
    platforms: [
        .macOS(.v13)
    ],
	products: [
		.library(name: "Kineo", targets: ["Kineo"]),
		.executable(
			name: "kineo",
			targets: ["kineo-cli"]),
		.executable(
			name: "kineo-parse",
			targets: ["kineo-parse"]),
	],
	dependencies: [
		.package(url: "https://github.com/kasei/swift-sparql-syntax.git", .upToNextMinor(from: "0.2.11")),
//		.package(name: "SPARQLSyntax", url: "https://github.com/kasei/swift-sparql-syntax.git", .branch("update")),
		.package(url: "https://github.com/kasei/swift-serd.git", .upToNextMinor(from: "0.0.4")),
		.package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMinor(from: "1.5.0")),
		.package(url: "https://github.com/kylef/URITemplate.swift.git", .upToNextMinor(from: "3.0.1")),
		.package(url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.11.5")),
//		.package(name: "SQLite.swift", url: "https://github.com/kasei/SQLite.swift.git", .branch("fix-swift-4")),
		.package(url: "https://github.com/kasei/diomede.git", .upToNextMinor(from: "0.0.65")),
		.package(url: "https://github.com/kasei/IDPPlanner.git", .upToNextMinor(from: "0.0.5")),
		.package(url: "https://github.com/apple/swift-algorithms", .upToNextMinor(from: "0.1.0")),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
	],
	targets: [
		.target(
			name: "Kineo",
			dependencies: [
				"CryptoSwift",
                .product(name: "SPARQLSyntax", package: "swift-sparql-syntax"),
                .product(name: "URITemplate", package: "URITemplate.swift"),
                .product(name: "serd", package: "swift-serd"),
				.product(name: "SQLite", package: "SQLite.swift"),
				.product(name: "DiomedeQuadStore", package: "Diomede"),
				.product(name: "IDPPlanner", package: "IDPPlanner"),
				.product(name: "Algorithms", package: "swift-algorithms"),
			]
		),
		.executableTarget(
			name: "kineo-cli",
			dependencies: [
				"Kineo",
				.product(name: "SPARQLSyntax", package: "swift-sparql-syntax"),
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		),
		.executableTarget(
			name: "kineo-client",
			dependencies: ["Kineo", .product(name: "SPARQLSyntax", package: "swift-sparql-syntax")]
		),
		.executableTarget(
			name: "kineo-dawg-test",
			dependencies: ["Kineo", .product(name: "SPARQLSyntax", package: "swift-sparql-syntax")]
		),
		.executableTarget(
			name: "kineo-parse",
			dependencies: ["Kineo", .product(name: "SPARQLSyntax", package: "swift-sparql-syntax")]
		),
		.executableTarget(
			name: "kineo-test",
			dependencies: ["Kineo", .product(name: "SPARQLSyntax", package: "swift-sparql-syntax")]
		),
		.testTarget(name: "KineoTests", dependencies: ["Kineo"])
	]
)
