import PackageDescription

let package = Package(
    name: "Kineo",
    targets: [
        Target(
            name: "kineo-cli",
            dependencies: [
                .Target(name: "Kineo")
            ]
        ),
        Target(
            name: "kineo-parse",
            dependencies: [
                .Target(name: "Kineo")
            ]
        )
    ],
    dependencies: [
		.Package(url: "https://github.com/kasei/swift-serd.git", majorVersion: 0)
    ]
)

let lib = Product(name: "Kineo", type: .Library(.Dynamic), modules: "Kineo")
products.append(lib)
