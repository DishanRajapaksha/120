import AppKit

/// Observes OS lifecycle notifications that impact display-link stability.
final class SystemEventMonitor {
    var onWillSleep: (() -> Void)?
    var onDidWake: (() -> Void)?
    var onScreenParametersChanged: (() -> Void)?

    private struct ObserverToken {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private var observers: [ObserverToken] = []

    func start() {
        guard observers.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default

        observers.append(
            ObserverToken(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.willSleepNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.onWillSleep?()
                }
            ))

        observers.append(
            ObserverToken(
                center: workspaceCenter,
                token: workspaceCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.onDidWake?()
                }
            ))

        observers.append(
            ObserverToken(
                center: appCenter,
                token: appCenter.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.onScreenParametersChanged?()
                }
            ))
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    deinit {
        stop()
    }
}
