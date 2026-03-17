import Foundation
import os.process

let fileManager = FileManager.default
let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let certDir = supportDir.appendingPathComponent("ProxyMock/Certs/hosts", isDirectory: true)

let host = "config.teams.microsoft.com"
let hostDir = certDir.appendingPathComponent(host)
let p12Path = hostDir.appendingPathComponent("cert.p12")

if fileManager.fileExists(atPath: p12Path.path) {
    print("Cert exists for \(host)")
} else {
    print("No cert found. Creating test folder to see if bash shell script fails.")
}

let caCert = supportDir.appendingPathComponent("ProxyMock/Certs/ca.pem")
if fileManager.fileExists(atPath: caCert.path) {
    print("CA cert exists!")
} else {
    print("CA cert MISSING!")
}
