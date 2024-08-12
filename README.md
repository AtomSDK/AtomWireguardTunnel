# AtomWireguardTunnel for iOS, macOS & tvOS

This project contains a static library for iOS, tvOS, and macOS.

## Requirements

- iOS 15.0+
- macOS 12.0+
- tvOS 17.0+
- Go 1.19 (install using Homebrew)

```sh
brew install go
```

## Integration in Application

### Installation

AtomWireguardTunnel can be integrated into your project using Swift Package Manager (SPM).

1. Open your project in Xcode.
2. Select `File` > `Add Package Dependencies...`
3. Enter the URL of the AtomWireguardTunnel repository: `https://github.com/AtomSDK/AtomWireguardTunnel`
4. Specify the version or branch you want to use:
   - **Branch Name:** [Documentation](https://developer.apple.com/documentation/packagedescription/package/dependency/requirement-swift.enum/branch(_:))
   - **Exact Version:** [Documentation](https://developer.apple.com/documentation/packagedescription/package/dependency/requirement-swift.enum/exact(_:))
   - **Revision:** [Documentation](https://developer.apple.com/documentation/packagedescription/package/dependency/requirement-swift.enum/revision(_:))
   - **Up To Next Major Version:** [Documentation](https://developer.apple.com/documentation/packagedescription/package/dependency/requirement-swift.enum/uptonextmajor(from:))
   - **Up To Next Minor Version:** [Documentation](https://developer.apple.com/documentation/packagedescription/package/dependency/requirement-swift.enum/uptonextminor(from:))
5. Add AtomWireguardTunnel to your project.

### Additional Steps

`WireGuardKit` links against the `wireguard-go-bridge` library, but it cannot build it automatically due to Swift Package Manager limitations. Follow these steps to create build targets for `wireguard-go-bridge`:

1. In Xcode, click `File` -> `New` -> `Target`. Switch to the "Other" tab and choose "External Build System".
2. Type `WireGuardGoBridge<PLATFORM>` under the "Product name", replacing `<PLATFORM>` with the appropriate platform name (`iOS`, `macOS`, or `tvOS`). Ensure the build tool is set to `/usr/bin/make`.
3. In the newly created target's "Info" tab, set the "Directory" path under "External Build Tool Configuration":

    ```sh
    $BUILD_DIR/../../SourcePackages/checkouts/AtomWireguardTunnel/Sources/AtomWireguardTunnel/build_wireguard_go_bridge.sh
    ```

4. In the "Build Settings" tab, set `SDKROOT` to `macosx` for macOS, `iphoneos` for iOS, or `appletvos` for tvOS.
5. Go to your Xcode project settings, locate your network extension target, and switch to the "Build Phases" tab.
   - In the "Target Dependencies" section, add `WireGuardGoBridge<PLATFORM>`.
   - In the "Link with Binary Libraries" section, add `AtomWireguardTunnel` if it is not there already.

Repeat steps 2-5 for each platform if you ship your app for iOS, tvOS, and macOS.

## Usage

To use AtomWireguardTunnel in your code, import it in your network extension:

```swift
import AtomWireGuardAppExtension
```

Update your `PacketTunnelProvider` implementation:

```swift
class PacketTunnelProvider: WireGuardTunnelProvider {
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Add code here to start the process of connecting the tunnel.
        super.startTunnel(options: options, completionHandler: completionHandler)
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Add code here to start the process of stopping the tunnel.
        super.stopTunnel(with: reason, completionHandler: completionHandler)
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        super.handleAppMessage(messageData, completionHandler: completionHandler)
    }
}
```