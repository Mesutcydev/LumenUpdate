import ArgumentParser

@main
struct LumenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lumen",
        abstract: "Lumen Update — secure macOS application update publisher CLI",
        version: "0.2.0",
        subcommands: [
            InitCommand.self,
            DoctorCommand.self,
            KeyCommand.self,
            RootCommand.self,
            PackageCommand.self,
            ReleaseCommand.self,
            PublishCommand.self,
            RepositoryCommand.self,
            ServeCommand.self,
        ]
    )
}
