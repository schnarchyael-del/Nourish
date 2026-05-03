import Foundation
import CloudKit
import Observation
import UIKit

// MARK: - Partner Sync
// TODO: Enable CloudKit capability in Xcode:
//   Signing & Capabilities → + Capability → CloudKit
//   Add container "iCloud.com.yael.nourish" in App Store Connect, then build.

@Observable
final class PartnerSyncManager {
    static let shared = PartnerSyncManager()

    private(set) var familyCode: String
    var isConnected: Bool = false
    var partnerLastSeen: Date? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    private let containerID = "iCloud.com.yael.nourish"
    private var database: CKDatabase {
        CKContainer(identifier: containerID).publicCloudDatabase
    }
    private let deviceID: String =
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    private init() {
        let saved = UserDefaults.standard.string(forKey: "familyCode") ?? ""
        if saved.isEmpty {
            let code = Self.makeCode()
            UserDefaults.standard.set(code, forKey: "familyCode")
            familyCode = code
        } else {
            familyCode = saved
        }
        isConnected = UserDefaults.standard.bool(forKey: "partnerConnected")
        if let ts = UserDefaults.standard.object(forKey: "partnerLastSeen") as? Double {
            partnerLastSeen = Date(timeIntervalSince1970: ts)
        }
    }

    private static func makeCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    func publishCode() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { @MainActor in isLoading = false } }
        do {
            let recordID = CKRecord.ID(recordName: "family-\(familyCode)")
            let record = CKRecord(recordType: "FamilySession", recordID: recordID)
            record["deviceID"] = deviceID as CKRecordValue
            record["familyCode"] = familyCode as CKRecordValue
            record["lastActive"] = Date.now as CKRecordValue
            try await database.save(record)
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't publish code. Enable CloudKit capability first."
            }
        }
    }

    func joinWithCode(_ code: String) async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { @MainActor in isLoading = false } }
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        do {
            let recordID = CKRecord.ID(recordName: "family-\(normalized)")
            let record = try await database.record(for: recordID)
            await MainActor.run {
                if let ts = (record["lastActive"] as? Date)?.timeIntervalSince1970 {
                    partnerLastSeen = Date(timeIntervalSince1970: ts)
                    UserDefaults.standard.set(ts, forKey: "partnerLastSeen")
                }
                isConnected = true
                UserDefaults.standard.set(true, forKey: "partnerConnected")
                UserDefaults.standard.set(normalized, forKey: "partnerJoinedCode")
            }
        } catch {
            await MainActor.run {
                errorMessage = "Code not found. Ask your partner to open the app first."
            }
        }
    }

    func disconnect() {
        isConnected = false
        partnerLastSeen = nil
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: "partnerConnected")
        UserDefaults.standard.removeObject(forKey: "partnerJoinedCode")
        UserDefaults.standard.removeObject(forKey: "partnerLastSeen")
    }
}
