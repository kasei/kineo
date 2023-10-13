// swift-tools-version:5.2
import PackageDescription

let package = Package(
	name: "Kineo",
	platforms: [.macOS(.v10_15)],
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
		.package(name: "SPARQLSyntax", url: "https://github.com/kasei/swift-sparql-syntax.git", .upToNextMinor(from: "0.2.0")),
//		.package(name: "SPARQLSyntax", url: "https://github.com/kasei/swift-sparql-syntax.git", .branch("update")),
		.package(name: "Cserd", url: "https://github.com/kasei/swift-serd.git", .upToNextMinor(from: "0.0.4")),
		.package(name: "CryptoSwift", url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMinor(from: "1.5.0")),
		.package(name: "URITemplate", url: "https://github.com/kylef/URITemplate.swift.git", .upToNextMinor(from: "3.0.1")),
		.package(name: "SQLite.swift", url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.11.5")),
//		.package(name: "SQLite.swift", url: "https://github.com/kasei/SQLite.swift.git", .branch("fix-swift-4")),
		.package(name: "Diomede", url: "https://github.com/kasei/diomede.git", .upToNextMinor(from: "0.0.64")),
		.package(name: "IDPPlanner", url: "https://github.com/kasei/IDPPlanner.git", .upToNextMinor(from: "0.0.5")),
		.package(url: "https://github.com/apple/swift-algorithms", .upToNextMinor(from: "0.1.0")),
	],
	targets: [
		.target(
			name: "Kineo",
			dependencies: [
				"CryptoSwift",
				"SPARQLSyntax",
				"URITemplate",
				.product(name: "serd", package: "Cserd"),
				.product(name: "SQLite", package: "SQLite.swift"),
				.product(name: "DiomedeQuadStore", package: "Diomede"),
				.product(name: "IDPPlanner", package: "IDPPlanner"),
				.product(name: "Algorithms", package: "swift-algorithms"),
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
