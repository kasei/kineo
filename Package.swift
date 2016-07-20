import PackageDescription

let package = Package(
    name: "Kineo",
    targets: [
        Target(
            name: "kineo-cli",
            dependencies: [
                .Target(name: "Kineo")
            ]
        )
    ],
    dependencies: []
)

let lib = Product(name: "Kineo", type: .Library(.Dynamic), modules: "Kineo")
products.append(lib)
