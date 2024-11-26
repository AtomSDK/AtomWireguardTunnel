// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import AtomWireGuardCore
import AtomWireGuardManager
import WireGuardKit
import Foundation
import NetworkExtension
import os

enum WireGuardExceptions: String {
    case HandshakeDidnotCompleted = "Handshake did not complete after"
    case HandshakeCompleted = "Received handshake response"

}

public var handshakeExceptionCount = 0

open class WireGuardTunnelProvider: NEPacketTunnelProvider {
    
    private var networkMonitor: NWPathMonitor?

    deinit {
        networkMonitor?.cancel()
    }
    
    /// A system completion handler passed from startTunnel and saved for later use once the
    /// connection is established.
    private var startTunnelCompletionHandler: (() -> Void)?
    private var originalConfiguration: String?
    private var snoozeTimerTask: Task<Void, Never>?

    private lazy var adapter: WireGuardAdapter = {
        return WireGuardAdapter(with: self) { logLevel, message in
            wg_log(logLevel.osLogLevel, message: message)
            self.handleExceptions(message);
        }
    }()
    
    // MARK: - startTunnel Method
    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            fatalError("Not a NETunnelProviderProtocol")
        }
        
        guard let appGroup = tunnelProviderProtocol.providerConfiguration?["AppGroup"] as? String else {
            fatalError("AppGroup not found in providerConfiguration")
        }

        guard let configs = tunnelProviderProtocol.providerConfiguration?["Configs"] as? String else {
            fatalError("AppGroup not found in providerConfiguration")
        }
        
        originalConfiguration = configs
        
        guard let tunnelConfiguration = try? TunnelConfiguration(fromWgQuickConfig: configs, called: "tunnel")
        else {
            wg_log(.info, message: WireGuardProviderError.savedProtocolConfigurationIsInvalid.rawValue)
            return;
        }
        
        var handle: Int32 = -1
        
        networkMonitor = NWPathMonitor()
            networkMonitor?.pathUpdateHandler = { path in
                guard handle >= 0 else { return }
                if path.status == .satisfied {
                    wg_log(.debug, message: "Network change detected, re-establishing sockets and IPs: \(path.availableInterfaces)")
                    }
        }
        
        networkMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
        
        // Start the tunnel
        adapter.start(tunnelConfiguration: tunnelConfiguration) { adapterError in
            guard let adapterError = adapterError else {
                let interfaceName = self.adapter.interfaceName ?? "unknown"
                
                wg_log(.info, message: "Tunnel interface is \(interfaceName)")
            
                self.startTunnelCompletionHandler =
                { [weak self] in
                    
                    completionHandler(nil)
                }
                return
            }
            
            switch adapterError {
            case .cannotLocateTunnelFileDescriptor:
                wg_log(.error, staticMessage: "Starting tunnel failed: could not determine file descriptor")
                wg_log(.error, message: WireGuardProviderError.couldNotDetermineFileDescriptor.rawValue)
                completionHandler(WireGuardProviderError.couldNotDetermineFileDescriptor)
                
            case .dnsResolution(let dnsErrors):
                let hostnamesWithDnsResolutionFailure = dnsErrors.map { $0.address }
                    .joined(separator: ", ")
                wg_log(.error, message: "DNS resolution failed for the following hostnames: \(hostnamesWithDnsResolutionFailure)")
                wg_log(.error, message: WireGuardProviderError.dnsResolutionFailure.rawValue)
                completionHandler(WireGuardProviderError.dnsResolutionFailure)
                
            case .setNetworkSettings(let error):
                wg_log(.error, message: "Starting tunnel failed with setTunnelNetworkSettings returning \(error.localizedDescription)")
                wg_log(.error, message: WireGuardProviderError.couldNotSetNetworkSettings.rawValue)

                completionHandler(WireGuardProviderError.couldNotSetNetworkSettings)
                
            case .startWireGuardBackend(let errorCode):
                wg_log(.error, message: "Starting tunnel failed with wgTurnOn returning \(errorCode)")
                wg_log(.error, message: WireGuardProviderError.couldNotStartBackend.rawValue)
                completionHandler(WireGuardProviderError.couldNotStartBackend)
                
            case .invalidState:
                // Must never happen
                fatalError()
            }
        }
    }
    
    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        wg_log(.info, staticMessage: "Stopping tunnel")
        
        startTunnelCompletionHandler = nil

        adapter.stop { error in
            
            if let error = error {
                wg_log(.error, message: "Failed to stop WireGuard adapter: \(error.localizedDescription)")
            }
            completionHandler()
            
#if os(macOS)
            // HACK: This is a filthy hack to work around Apple bug 32073323 (dup'd by us as 47526107).
            // Remove it when they finally fix this upstream and the fix has been rolled out to
            // sufficient quantities of users.
            exit(0)
#endif
        }
    }
    

    
    open func handleExceptions(_ message: String?){
        
        if let exceptionMessage = message {
            switch exceptionMessage {
            case _ where exceptionMessage.contains(WireGuardExceptions.HandshakeDidnotCompleted.rawValue):
                handshakeExceptionCount = handshakeExceptionCount + 1
                wg_log(.error, message: "(\(handshakeExceptionCount) \(WireGuardExceptions.HandshakeDidnotCompleted.rawValue)")
                if handshakeExceptionCount >= 3 {
                    /**
                     * For iOS:
                     * Removed self.stopTunnel and used cancelTunnelWithError because the tunnel was not stopping.
                     * Apple documentation says:
                     * Do not use this method to stop the tunnel from the Packet Tunnel Provider. Use cancelTunnelWithError: instead.
                     * https://developer.apple.com/documentation/networkextension/nepackettunnelprovider/1406192-stoptunnel
                     * ***************************************
                     * For macOS:
                     * In macOS case after calling cancelTunnelWithError the handshake packets were being sent, this might be a bug in Apple for macOS.
                     * Remove the macOS case below if the bug resolves in future releases.
                     * Ideally cancelTunnelWithError should work for both iOS and macOS.
                     */
#if os(macOS)
                    self.stopTunnel(with: NEProviderStopReason.connectionFailed) {
                        //
                    }
#else
                    self.cancelTunnelWithError(WireGuardProviderError.handshakeFailure)
#endif
                }
            case _ where exceptionMessage.contains(WireGuardExceptions.HandshakeCompleted.rawValue):
                wg_log(.info, message: "(\(WireGuardExceptions.HandshakeCompleted.rawValue)")
                startTunnelCompletionHandler?()
                startTunnelCompletionHandler = nil

            default:
                break
            }
        }
    }
    
    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let completionHandler = completionHandler else { return }
        
        guard let action = String(data: messageData, encoding: .utf8) else {
            completionHandler(nil)
            return
        }
        
        switch action {
        case "pause":
            pauseVPN(20)
        case "resume":
            resumeVPN()
        default:
            break
        }
        
        completionHandler(messageData)
    }
    
    private func startTunnel(onDemand: Bool) async throws {
        do {
            
            guard let configs = originalConfiguration as? String else {
                fatalError("original Configration not found")
            }
            guard let tunnelConfiguration = try? TunnelConfiguration(fromWgQuickConfig: configs, called: "tunnel")
            else {
                wg_log(.info, message: WireGuardProviderError.savedProtocolConfigurationIsInvalid.rawValue)
                return;
            }
            try await startTunnel(with: tunnelConfiguration, onDemand: onDemand)
            
        } catch {
            
            throw error
        }
    }
    
    private func startTunnel(with tunnelConfiguration: TunnelConfiguration, onDemand: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
                if let adapterError = error {
                    continuation.resume(throwing: adapterError)
                    return
                }

                guard let self = self else {
                    continuation.resume(throwing: WireGuardProviderError.dnsResolutionFailure)
                    return
                }

                let interfaceName = self.adapter.interfaceName ?? "unknown"
                wg_log(.info, message: "Tunnel interface is \(interfaceName)")

                // Resume the continuation indicating success
                continuation.resume(returning: ())

                // Proceed with additional tasks on the main actor if needed
                Task { @MainActor in
                    // Additional main actor tasks
                }
            }
        }
    }
    
    @MainActor
    public func stopMonitors() async {

    }
    
    // MARK: - Snooze
    
    private func pauseVPN(_ duration: TimeInterval, completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            await startPauseVPN(duration: duration)
            completionHandler?(nil)
        }
    }
    
    private func resumeVPN(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            await cancelPauseVPN()
            completionHandler?(nil)
        }
    }
    
    
    private var pauseRequestProcessing: Bool = false
    
    @MainActor
    private func startPauseVPN(duration: TimeInterval) async {
        if pauseRequestProcessing {
            wg_log(.error, message: "Rejecting start pause request due to existing request processing")

            return
        }
        
        pauseRequestProcessing = true
        wg_log(.error, message: "Starting pause mode with duration: \(duration)")
        await stopMonitors()
        
        self.adapter.snooze { [weak self] error in
            guard let self else {
                assertionFailure("Failed to get strong self")
                return
            }
            
            if error == nil {
                // Schedule resumption after the specified duration
                snoozeTimerTask = Task {
                    await self.resumeAfterSnooze(duration: duration)
                }
            }
            
            self.pauseRequestProcessing = false
        }
        

    }
    
    private func cancelPauseVPN() async {
        guard !pauseRequestProcessing else {
            wg_log(.error, message: "Rejecting cancel pause request due to existing request processing")
            return
        }

        pauseRequestProcessing = true
        
        defer {
            wg_log(.info, message: "Exiting cancelPauseVPN; resetting snoozeRequestProcessing")
            pauseRequestProcessing = false
        }

        snoozeTimerTask?.cancel()
        snoozeTimerTask = nil

        wg_log(.error, message: "Canceling pause mode")

        // Attempt to restart the tunnel
        do {
            try await startTunnel(onDemand: false)
        } catch {
            wg_log(.error, message: "Failed to restart tunnel: \(error.localizedDescription)")
        }
    }
    
    private func resumeAfterSnooze(duration: TimeInterval) async {
        do {
            wg_log(.info, message: "Scheduling VPN resumption in \(duration) seconds")

            // Wait for the snooze duration
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            // Check if the task has been canceled
            guard !Task.isCancelled else {
                wg_log(.info, message: "pause task was canceled before resumption")
                return
            }

            // Resume the VPN connection
            try await startTunnel(onDemand: false)
            wg_log(.info, message: "VPN resumed successfully after pause duration")
        } catch {
            wg_log(.error, message: "Cancelled auto resume VPN after pause: \(error.localizedDescription)")
        }
    }
}


extension WireGuardLogLevel {
    var osLogLevel: OSLogType {
        switch self {
        case .verbose:
            return .debug
        case .error:
            return .error
        }
    }
}
