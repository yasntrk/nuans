import Foundation

/// Identifies the hardware a profile belongs to.
///
/// `UIDevice.model` is useless here: it returns "iPhone" for every iPhone ever
/// made, while a colour profile is only valid for one sensor. The `uname`
/// machine string is the model identifier, such as `iPhone15,2`, which is what
/// the profile is keyed on together with the lens identifier.
enum DeviceIdentity {
    static let hardwareModel: String = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(_SYS_NAMELEN)
            ) { String(cString: $0) }
        }
        return machine.isEmpty ? "unknown" : machine
    }()
}
