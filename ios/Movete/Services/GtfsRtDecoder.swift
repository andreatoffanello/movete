import Foundation

// MARK: - GTFS-RT Protobuf Decoder
//
// Minimal protobuf binary decoder for GTFS-RT feeds.
// Handles VehiclePosition, TripUpdate, and Alert entities.
// No external dependencies — pure Swift.

// MARK: - Decode Vehicle Positions

func decodeGtfsRtVehicles(from data: Data) -> [Vehicle] {
    var reader = ProtoReader(data: data)
    var vehicles: [Vehicle] = []
    while let tag = reader.readTag() {
        if tag.field == 2 && tag.wire == 2 {
            if let v = decodeVehicleEntity(reader.readLengthDelimited()) {
                vehicles.append(v)
            }
        } else {
            reader.skipField(wireType: tag.wire)
        }
    }
    return vehicles
}

private func decodeVehicleEntity(_ data: Data) -> Vehicle? {
    var r = ProtoReader(data: data)
    var entityId = ""
    var vp: VehicleRaw?
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2): entityId = r.readString()
        case (4, 2): vp = decodeVehiclePosition(r.readLengthDelimited())
        default: r.skipField(wireType: tag.wire)
        }
    }
    guard let v = vp, (v.lat != 0 || v.lng != 0) else { return nil }
    return Vehicle(
        id: entityId, tripId: v.tripId, routeId: v.routeId, label: v.label,
        latitude: Double(v.lat), longitude: Double(v.lng),
        bearing: v.bearing != 0 ? Double(v.bearing) : nil,
        speed: v.speed != 0 ? Double(v.speed) : nil,
        timestamp: Date(timeIntervalSince1970: TimeInterval(v.timestamp)),
        currentStopSequence: v.currentStopSequence != 0 ? Int(v.currentStopSequence) : nil,
        stopId: v.stopId.isEmpty ? nil : v.stopId,
        occupancyStatus: Vehicle.OccupancyStatus(rawValue: Int(v.occupancyStatus)) ?? .unknown
    )
}

private struct VehicleRaw {
    var tripId = "", routeId = "", label = "", stopId = ""
    var lat: Float = 0, lng: Float = 0, bearing: Float = 0, speed: Float = 0
    var timestamp: UInt64 = 0
    var currentStopSequence: UInt32 = 0
    var occupancyStatus: UInt32 = 0
    var currentStatus: UInt32 = 0
}

private func decodeVehiclePosition(_ data: Data) -> VehicleRaw {
    var r = ProtoReader(data: data)
    var v = VehicleRaw()
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2):
            let (t, ro) = decodeTripDescriptor(r.readLengthDelimited())
            v.tripId = t; v.routeId = ro
        case (2, 2):
            let raw = r.readLengthDelimited()
            let (la, lo, be, sp) = decodePosition(raw)
            if la != 0 || lo != 0 {
                v.lat = la; v.lng = lo; v.bearing = be; v.speed = sp
            } else {
                v.label = decodeVehicleDescriptorLabel(raw)
            }
        case (3, 2):
            let (la, lo, be, sp) = decodePosition(r.readLengthDelimited())
            v.lat = la; v.lng = lo; v.bearing = be; v.speed = sp
        case (4, 0): v.currentStatus = UInt32(r.readVarint())
        case (5, 0): v.timestamp = r.readVarint()
        case (6, 0): v.currentStopSequence = UInt32(r.readVarint())
        case (7, 2): v.stopId = r.readString()
        case (9, 0): v.occupancyStatus = UInt32(r.readVarint())
        default: r.skipField(wireType: tag.wire)
        }
    }
    return v
}

// MARK: - Decode Trip Updates

func decodeGtfsRtTripUpdates(from data: Data) -> [TripUpdate] {
    var reader = ProtoReader(data: data)
    var updates: [TripUpdate] = []
    while let tag = reader.readTag() {
        if tag.field == 2 && tag.wire == 2 {
            if let tu = decodeTripUpdateEntity(reader.readLengthDelimited()) {
                updates.append(tu)
            }
        } else {
            reader.skipField(wireType: tag.wire)
        }
    }
    return updates
}

private func decodeTripUpdateEntity(_ data: Data) -> TripUpdate? {
    var r = ProtoReader(data: data)
    var tripUpdate: TripUpdate?
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (3, 2): tripUpdate = decodeTripUpdateMessage(r.readLengthDelimited())
        default: r.skipField(wireType: tag.wire)
        }
    }
    return tripUpdate
}

private func decodeTripUpdateMessage(_ data: Data) -> TripUpdate? {
    var r = ProtoReader(data: data)
    var tripId = "", routeId = ""
    var stopTimeUpdates: [StopTimeUpdate] = []
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2):
            let (t, ro) = decodeTripDescriptor(r.readLengthDelimited())
            tripId = t; routeId = ro
        case (2, 2):
            if let stu = decodeStopTimeUpdate(r.readLengthDelimited()) {
                stopTimeUpdates.append(stu)
            }
        default: r.skipField(wireType: tag.wire)
        }
    }
    guard !tripId.isEmpty else { return nil }
    return TripUpdate(id: tripId, routeId: routeId, stopTimeUpdates: stopTimeUpdates)
}

private func decodeStopTimeUpdate(_ data: Data) -> StopTimeUpdate? {
    var r = ProtoReader(data: data)
    var stopSequence: Int = 0
    var stopId = ""
    var arrivalDelay: Int?
    var departureDelay: Int?
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 0): stopSequence = Int(r.readVarint())
        case (2, 2): arrivalDelay = decodeStopTimeEvent(r.readLengthDelimited())
        case (3, 2): departureDelay = decodeStopTimeEvent(r.readLengthDelimited())
        case (4, 2): stopId = r.readString()
        default: r.skipField(wireType: tag.wire)
        }
    }
    return StopTimeUpdate(
        stopSequence: stopSequence, stopId: stopId,
        arrivalDelay: arrivalDelay, departureDelay: departureDelay
    )
}

private func decodeStopTimeEvent(_ data: Data) -> Int? {
    var r = ProtoReader(data: data)
    var delay: Int?
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 0):
            let raw = r.readVarint()
            // Protobuf int32 is sign-extended to 64 bits; truncate safely
            delay = Int(Int32(truncatingIfNeeded: raw))
        default: r.skipField(wireType: tag.wire)
        }
    }
    return delay
}

// MARK: - Decode Service Alerts

func decodeGtfsRtAlerts(from data: Data) -> [ServiceAlert] {
    var reader = ProtoReader(data: data)
    var alerts: [ServiceAlert] = []
    while let tag = reader.readTag() {
        if tag.field == 2 && tag.wire == 2 {
            if let a = decodeAlertEntity(reader.readLengthDelimited()) {
                alerts.append(a)
            }
        } else {
            reader.skipField(wireType: tag.wire)
        }
    }
    return alerts
}

private func decodeAlertEntity(_ data: Data) -> ServiceAlert? {
    var r = ProtoReader(data: data)
    var entityId = ""
    var alert: ServiceAlert?
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2): entityId = r.readString()
        case (5, 2): alert = decodeAlertMessage(r.readLengthDelimited(), entityId: entityId)
        default: r.skipField(wireType: tag.wire)
        }
    }
    return alert
}

private func decodeAlertMessage(_ data: Data, entityId: String) -> ServiceAlert? {
    var r = ProtoReader(data: data)
    var headerText = "", descText = ""
    var routeIds: [String] = []
    var stopIds: [String] = []
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (5, 2):
            let (rid, sid) = decodeEntitySelector(r.readLengthDelimited())
            if !rid.isEmpty { routeIds.append(rid) }
            if !sid.isEmpty { stopIds.append(sid) }
        case (10, 2): headerText = decodeTranslatedString(r.readLengthDelimited())
        case (11, 2): descText = decodeTranslatedString(r.readLengthDelimited())
        default: r.skipField(wireType: tag.wire)
        }
    }
    guard !headerText.isEmpty else { return nil }
    return ServiceAlert(
        id: entityId, headerText: headerText, descriptionText: descText,
        affectedRouteIds: routeIds, affectedStopIds: stopIds,
        activePeriodStart: nil, activePeriodEnd: nil
    )
}

private func decodeEntitySelector(_ data: Data) -> (routeId: String, stopId: String) {
    var r = ProtoReader(data: data)
    var routeId = "", stopId = ""
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (3, 2): routeId = r.readString()
        case (5, 2): stopId = r.readString()
        default: r.skipField(wireType: tag.wire)
        }
    }
    return (routeId, stopId)
}

private func decodeTranslatedString(_ data: Data) -> String {
    var r = ProtoReader(data: data)
    while let tag = r.readTag() {
        if tag.field == 1 && tag.wire == 2 {
            return decodeTranslation(r.readLengthDelimited())
        } else {
            r.skipField(wireType: tag.wire)
        }
    }
    return ""
}

private func decodeTranslation(_ data: Data) -> String {
    var r = ProtoReader(data: data)
    var text = ""
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2): text = r.readString()
        default: r.skipField(wireType: tag.wire)
        }
    }
    return text
}

// MARK: - Shared helpers

private func decodeTripDescriptor(_ data: Data) -> (tripId: String, routeId: String) {
    var r = ProtoReader(data: data)
    var tripId = "", routeId = ""
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2): tripId = r.readString()
        case (3, 2): routeId = r.readString()
        default: r.skipField(wireType: tag.wire)
        }
    }
    return (tripId, routeId)
}

private func decodeVehicleDescriptorLabel(_ data: Data) -> String {
    var r = ProtoReader(data: data)
    var label = ""
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (2, 2): label = r.readString()
        default: r.skipField(wireType: tag.wire)
        }
    }
    return label
}

private func decodePosition(_ data: Data) -> (lat: Float, lng: Float, bearing: Float, speed: Float) {
    var r = ProtoReader(data: data)
    var lat: Float = 0, lng: Float = 0, bearing: Float = 0, speed: Float = 0
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 5): lat = Float(bitPattern: r.readFixed32())
        case (2, 5): lng = Float(bitPattern: r.readFixed32())
        case (3, 5): bearing = Float(bitPattern: r.readFixed32())
        case (4, 5): speed = Float(bitPattern: r.readFixed32())
        default: r.skipField(wireType: tag.wire)
        }
    }
    return (lat, lng, bearing, speed)
}

// MARK: - Proto binary reader

private struct ProtoReader {
    let data: Data
    var pos: Int = 0

    var hasMore: Bool { pos < data.count }

    mutating func readByte() -> UInt8? {
        guard pos < data.count else { return nil }
        defer { pos += 1 }
        return data[pos]
    }

    mutating func readVarint() -> UInt64 {
        var result: UInt64 = 0
        var shift = 0
        while let byte = readByte() {
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    mutating func readFixed32() -> UInt32 {
        guard pos + 4 <= data.count else { pos = data.count; return 0 }
        let value = data[pos..<pos+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        pos += 4
        return value.littleEndian
    }

    mutating func readFixed64() -> UInt64 {
        guard pos + 8 <= data.count else { pos = data.count; return 0 }
        let value = data[pos..<pos+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        pos += 8
        return value.littleEndian
    }

    mutating func readLengthDelimited() -> Data {
        let len = Int(readVarint())
        guard pos + len <= data.count else { pos = data.count; return Data() }
        let slice = Data(data[pos..<pos+len])
        pos += len
        return slice
    }

    mutating func readString() -> String {
        let bytes = readLengthDelimited()
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    mutating func skipField(wireType: Int) {
        switch wireType {
        case 0: _ = readVarint()
        case 1: _ = readFixed64()
        case 2: _ = readLengthDelimited()
        case 5: _ = readFixed32()
        default: pos = data.count
        }
    }

    mutating func readTag() -> (field: Int, wire: Int)? {
        guard hasMore else { return nil }
        let v = readVarint()
        return (field: Int(v >> 3), wire: Int(v & 0x7))
    }
}
