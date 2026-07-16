import ServiceManagement

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let enabledValue: () -> Bool
    private let registerAction: () throws -> Void
    private let unregisterAction: () throws -> Void

    init(
        isEnabled: @escaping () -> Bool = { SMAppService.mainApp.status == .enabled },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        enabledValue = isEnabled
        registerAction = register
        unregisterAction = unregister
    }

    var isEnabled: Bool { enabledValue() }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else { return }
        do {
            if enabled { try registerAction() }
            else { try unregisterAction() }
        } catch {
            throw AppError.launchAtLogin
        }
    }
}
