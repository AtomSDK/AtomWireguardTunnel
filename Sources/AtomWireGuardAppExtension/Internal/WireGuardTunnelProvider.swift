import AtomWireGuardCore
import AtomWireGuardManager
import WireGuardKit

// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

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

    private lazy var adapter: WireGuardAdapter = {
        return WireGuardAdapter(with: self) { logLevel, message in
            wg_log(logLevel.osLogLevel, message: message)
            self.handleExceptions(message);
        }
    }()
    
    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        // BEGIN: TunnelKit
        
        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            fatalError("Not a NETunnelProviderProtocol")
        }
        guard let appGroup = tunnelProviderProtocol.providerConfiguration?["AppGroup"] as? String else {
            fatalError("AppGroup not found in providerConfiguration")
        }
        
        guard let configs = tunnelProviderProtocol.providerConfiguration?["Configs"] as? String else {
            fatalError("AppGroup not found in providerConfiguration")
        }
        
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
                    self.stopTunnel(with: NEProviderStopReason.noNetworkAvailable) {
                        
                    }
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
        
        if messageData.count == 1 && messageData[0] == 0 {
            adapter.getRuntimeConfiguration { settings in
                var data: Data?
                if let settings = settings {
                    data = settings.data(using: .utf8)!
                }
                completionHandler(data)
            }
        } else {
            completionHandler(nil)
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
