import Foundation

/// Utility to retrieve device network information
struct NetworkInfo {
    
    /// Gets the current local IPv4 address of the Mac on the active network interface (e.g., en0, en1, etc.)
    /// Returns "127.0.0.1" if no active external interface is found.
    static func getLocalIPAddress() -> String {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        
        guard getifaddrs(&ifaddr) == 0 else {
            return address
        }
        guard let firstAddr = ifaddr else {
            return address
        }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Check for IPv4 addresses
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                
                // Exclude loopback/virtual interfaces, prefer primary ethernet/wifi
                if name.hasPrefix("en") || name.hasPrefix("eth") || name.hasPrefix("wl") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                socklen_t(0),
                                NI_NUMERICHOST)
                    
                    address = String(cString: hostname)
                    // If we found a valid IPv4 that isn't localhost, break early and use it
                    if address != "127.0.0.1" {
                        break
                    }
                }
            }
        }
        
        freeifaddrs(ifaddr)
        return address
    }
}
