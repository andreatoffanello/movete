import Foundation
import CoreLocation

// MARK: - Transit Types

enum TransitType: String, Codable, CaseIterable {
    case bus
    case tram
    case metro
    case rail
    case ferry
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = TransitType(rawValue: value) ?? .unknown
    }

    var sfSymbol: String {
        switch self {
        case .bus:     return "bus.fill"
        case .tram:    return "tram.fill"
        case .metro:   return "train.side.rear.car"
        case .rail:    return "train.side.front.car"
        case .ferry:   return "ferry.fill"
        case .unknown: return "bus.fill"
        }
    }
}

// MARK: - Core Response (core.json)

struct CoreData: Codable {
    let operator_info: OperatorInfo
    let lastUpdated: String
    let validUntil: String
    let headsigns: [String]
    let lineNames: [String]
    let routeIds: [String]
    let routes: [Route]
    let stops: [Stop]

    enum CodingKeys: String, CodingKey {
        case operator_info = "operator"
        case lastUpdated, validUntil, headsigns, lineNames, routeIds, routes, stops
    }
}

struct OperatorInfo: Codable {
    let id: String
    let name: String
    let url: String?
}

// MARK: - Stop (from core.json — no departures)

struct Stop: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let lines: [String]?   // line names serving this stop

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Stop, rhs: Stop) -> Bool { lhs.id == rhs.id }
}

// MARK: - Route (from core.json — directions without shapes)

struct Route: Codable, Identifiable {
    let id: String
    let name: String
    let longName: String?
    let color: String
    let textColor: String
    let transitType: TransitType
    let directions: [RouteDirection]?

    var swiftColor: Color {
        Color(hex: color)
    }
}

struct RouteDirection: Codable {
    let id: Int
    let headsign: String
    let stopIds: [String]
    // shape loaded on-demand from routes/{id}.json
}

// MARK: - Stop Departures (from stops/{id}.json — on-demand)

struct StopSchedule: Codable {
    let id: String
    let departures: [String: [[DepartureValue]]]  // "mon,tue" -> [[time, lineIdx, headsignIdx, ...]]
}

/// A departure entry is a heterogeneous array: [time, lineIdx, headsignIdx, dock?, patternIdx?, tripIdx?]
enum DepartureValue: Codable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        }
    }

    var stringValue: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .string(_): return nil
        }
    }
}

// MARK: - Resolved Departure (UI-ready, built from indexed data)

struct Departure: Identifiable {
    let id: String          // tripId or generated
    let time: String        // "HH:mm"
    let minutes: Int        // minutes since midnight
    let lineName: String
    let lineColor: String
    let lineTextColor: String
    let headsign: String
    let transitType: TransitType
    let routeId: String
    let tripId: String?
    let dock: String?

    /// RT delay (nil = scheduled only)
    var delaySeconds: Int?

    var isLive: Bool { delaySeconds != nil }
}

import SwiftUI
