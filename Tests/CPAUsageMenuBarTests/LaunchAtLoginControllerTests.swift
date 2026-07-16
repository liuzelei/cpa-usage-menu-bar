import Testing
@testable import CPAUsageMenuBar

@Test
func enablingLaunchAtLoginRegistersService() throws {
    var registerCount = 0
    let controller = LaunchAtLoginController(
        isEnabled: { false },
        register: { registerCount += 1 },
        unregister: {}
    )

    try controller.setEnabled(true)

    #expect(registerCount == 1)
}

@Test
func disablingLaunchAtLoginUnregistersService() throws {
    var unregisterCount = 0
    let controller = LaunchAtLoginController(
        isEnabled: { true },
        register: {},
        unregister: { unregisterCount += 1 }
    )

    try controller.setEnabled(false)

    #expect(unregisterCount == 1)
}
