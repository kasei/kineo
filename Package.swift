// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Kineo",
	products: [
		.library(name: "Kineo", targets: ["Kineo"]),
	],    
    dependencies: [
		.package(url: "https://github.com/kasei/swift-sparql-parser.git", .branch("master")),
		.package(url: "https://github.com/kasei/swift-serd.git", from: "0.0.0"),
		.package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "0.8.0")
    ],
    targets: [
    	.target(
    		name: "Kineo",
			dependencies: ["CryptoSwift", "SPARQLParser"]
    	),
        .target(
            name: "kineo-cli",
            dependencies: ["Kineo"]
        ),
        .target(
            name: "kineo-parse",
            dependencies: ["Kineo"]
        ),
        .testTarget(name: "KineoTests", dependencies: ["Kineo"])
    ]
)

//let lib = Product(name: "Kineo", type: .Library(.Dynamic), modules: "Kineo")
//products.append(lib)
