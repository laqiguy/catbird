import Leaf
import Vapor

/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {
    // Register logger
    let logger = SystemLogger.default
    services.register(logger, as: Logger.self)
    config.prefer(SystemLogger.self, for: Logger.self)

    let appConfig = try AppConfig.detect()
    
    let fileStore = LogResponseStore(
        store: FileResponseStore(path: appConfig.mocksDirectory),
        logger: SystemLogger.category("File"))

    let dataResponseStore = DataResponseStore()
    let dataStore = LogResponseStore(
        store: dataResponseStore,
        logger: SystemLogger.category("Data"))

    // Register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    let apiController = APIController(store: dataStore)
    try router.register(collection: apiController)
    let webController = WebController(store: dataResponseStore)
    try router.register(collection: webController)
    services.register(router, as: Router.self)

    // Register middleware
    var middlewares = MiddlewareConfig() // Create _empty_ middleware config
    middlewares.use(ErrorMiddleware.self) // Catches errors and converts to HTTP response
    middlewares.use(FileMiddleware.self) // Serves static files from a public directory.

    switch appConfig.mode {
    case .write(let url):
        services.register { ProxyMiddleware(baseURL: url, logger: try $0.make()) }
        middlewares.use(ResponseWriterMiddleware(store: fileStore))
        middlewares.use(ProxyMiddleware.self)
        logger.info("Write mode")
    case .read:
        middlewares.use(ResponseReaderMiddleware(store: fileStore))
        middlewares.use(ResponseReaderMiddleware(store: dataStore))
        logger.info("Read mode")
    }

    services.register(middlewares)
    
    // Register view renderer
    let leafProvider = LeafProvider()
    try services.register(leafProvider)
    config.prefer(LeafRenderer.self, for: ViewRenderer.self)
    
    services.register(WriteModeCommand.self)
    services.register(ReadModeCommand.self)
    
    var commandConfig = CommandConfig()
    commandConfig.use(WriteModeCommand.self, as: "write")
    commandConfig.use(ReadModeCommand.self, as: "read")
    services.register(commandConfig)
}

struct ReadModeCommand: Command, ServiceType {
    static func makeService(for container: Container) throws -> ReadModeCommand {
        return .init()
    }
    
    var arguments: [CommandArgument] { return [] }
    var options: [CommandOption] {
        return [
            .value(name: "host", short: "h", default: "127.0.0.1", help: ["- Set the hostname the server will run on."]),
            .value(name: "port", short: "p", default: "8080", help: ["Set the port the server will run on."]),
            .value(name: "read_dir", short: "d", help: [" - Directory to write to"])
        ]
    }
    var help: [String] { return ["Start Catbird server in read mode"] }
    
    func run(using context: CommandContext) throws -> Future<Void> {
        
        let host = try context.requireOption("host")
        let port = try context.requireOption("port")
        let mockDir = try context.requireOption("read_dir")
        
        context.console.print("\(host):\(port) from \(mockDir)")
        
        return .done(on: context.container)
    }
}

struct WriteModeCommand: Command, ServiceType {
    static func makeService(for container: Container) throws -> WriteModeCommand {
        return .init()
    }
    
    var arguments: [CommandArgument] { return [] }
    var options: [CommandOption] {
        return [
            .value(name: "host", short: "h", default: "127.0.0.1", help: ["- Set the hostname the server will run on."]),
            .value(name: "port", short: "p", default: "8080", help: ["Set the port the server will run on."]),
            .value(name: "remote_host", short: "r", default: "127.0.0.1:8080", help: [" - Host to write from"]),
            .value(name: "write_dir", short: "d", help: [" - Directory to write to"])
        ]
    }
    var help: [String] { return ["Start Catbird server in write mode"] }
        
    func run(using context: CommandContext) throws -> Future<Void> {
    
        let host = try context.requireOption("host")
        let port = try context.requireOption("port")
        let mockDir = try context.requireOption("write_dir")
        let remote = try context.requireOption("remote_host")

        context.console.print("\(remote) through \(host):\(port) to \(mockDir)")

        return  .done(on: context.container)
    }
}
