import PackageDescription

let package = Package(
    name: "Kineo",
    dependencies: [],
    targets: [
        Target(
            name: "kineo-cli",
            dependencies: [
                .Target(name: "Kineo")
            ]
        )
    ]
)

let lib = Product(name: "Kineo", type: .Library(.Dynamic), modules: "Kineo")
products.append(lib)
