import Foundation
import FirebaseFirestore

extension FeedingSession {
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id":            id.uuidString,
            "startTime":     startTime,
            "feedType":      feedType.rawValue,
            "durationMins":  totalActiveMinutes,
        ]
        if let endTime           { data["endTime"] = endTime }
        if let leftDurationMins  { data["leftDurationMins"] = leftDurationMins }
        if let rightDurationMins { data["rightDurationMins"] = rightDurationMins }
        if let bottleContentType { data["bottleContentType"] = bottleContentType.rawValue }
        if let bottleAmountMl    { data["bottleAmountMl"] = bottleAmountMl }
        if let loggedByDeviceID  { data["loggedByDeviceID"] = loggedByDeviceID }
        if let pumpSide          { data["pumpSide"] = pumpSide.rawValue }
        if let pumpVolumeMl      { data["pumpVolumeMl"] = pumpVolumeMl }
        if let notes, !notes.isEmpty { data["notes"] = notes }
        return data
    }

    static func fromFirestoreData(_ data: [String: Any]) -> FeedingSession? {
        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let startTime = decodeDate(data["startTime"]),
            let feedTypeRaw = data["feedType"] as? String,
            let feedType = FeedType(rawValue: feedTypeRaw)
        else {
            return nil
        }

        let endTime = decodeDate(data["endTime"])

        var bottleContentType: BottleContentType?
        if let raw = data["bottleContentType"] as? String {
            bottleContentType = BottleContentType(rawValue: raw)
        }

        var pumpSide: PumpSide?
        if let raw = data["pumpSide"] as? String {
            pumpSide = PumpSide(rawValue: raw)
        }

        let session = FeedingSession(
            startTime: startTime,
            feedType: feedType,
            endTime: endTime,
            bottleContentType: bottleContentType,
            bottleAmountMl: data["bottleAmountMl"] as? Int,
            leftDurationMins: data["leftDurationMins"] as? Int,
            rightDurationMins: data["rightDurationMins"] as? Int,
            loggedByDeviceID: data["loggedByDeviceID"] as? String,
            pumpSide: pumpSide,
            pumpVolumeMl: data["pumpVolumeMl"] as? Int,
            notes: data["notes"] as? String
        )
        session.id = id
        return session
    }

    private static func decodeDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let date = value as? Date    { return date }
        return nil
    }
}
