import Darwin
import Foundation

public enum ProcessProbe {
    /// O processo existe e, quando `startedAt` é informado, começou nesse horário (±2 s).
    /// A checagem do horário evita confundir uma sessão morta com outro processo que herdou o PID.
    public static func isRunning(pid: Int32, startedAt expected: Date?) -> Bool {
        guard pid > 0 else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        guard let expected, let actual = startTime(of: pid) else { return true }
        return abs(actual.timeIntervalSince(expected)) < 2
    }

    static func startTime(of pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
