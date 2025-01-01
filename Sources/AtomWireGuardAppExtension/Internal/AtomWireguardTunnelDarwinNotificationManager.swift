//
/*
 * AtomWireguardTunnelDarwinNotificationManager.swift
 * AtomWireguardTunnel
 
 * Created by AtomSDK on 09/12/2024.
 * Copyright © 2024 AtomSDK. All rights reserved.
 */

import Foundation
@objc public class AtomWireguardTunnelDarwinNotificationManager: NSObject {
    
    @objc static let shared = AtomWireguardTunnelDarwinNotificationManager()
    
    private override init() {}
    
    // 1
    private var callbacks: [String: ([String : Any]?) -> Void] = [:]
    
    // Method to post a Darwin notification
    @objc func postNotification(name: String, userInfo: [String : Any]) {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        
        // Convert dictionary to CFDictionary
        let cfUserInfo: CFDictionary? = userInfo as CFDictionary?
        
        CFNotificationCenterPostNotification(notificationCenter,
                                             CFNotificationName(name as CFString),
                                             nil,
                                             cfUserInfo,
                                             true)
    }
    
    // 2
    @objc func startObserving(name: String, callback: @escaping ([String : Any]?) -> Void) {
        callbacks[name] = callback
        
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        
        CFNotificationCenterAddObserver(notificationCenter,
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        AtomWireguardTunnelDarwinNotificationManager.notificationCallback,
                                        name as CFString,
                                        nil,
                                        .deliverImmediately)
    }
    
    // 3
    @objc func stopObserving(name: String) {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(name as CFString), nil)
        callbacks.removeValue(forKey: name)
    }
    
    // 4
    private static let notificationCallback: CFNotificationCallback = { center, observer, name, _, userInfo in
        guard let observer = observer else { return }
        let manager = Unmanaged<AtomWireguardTunnelDarwinNotificationManager>.fromOpaque(observer).takeUnretainedValue()
        
        if let name = name?.rawValue as String?,
           let callback = manager.callbacks[name] {
            // Convert CFDictionary to Swift Dictionary
            let swiftUserInfo = userInfo as? [String: Any]
            
            callback(swiftUserInfo)
        }
    }
}
