import Foundation
import Combine

@MainActor
final class PairingManager: ObservableObject {
    static let shared = PairingManager()

    @Published private(set) var pairingCode: String?
    @Published private(set) var isPaired = false
    @Published private(set) var statusMessage = "Not paired"
    @Published private(set) var lastError: String?
    @Published private(set) var pairedEmail: String?

    private var pairingSecret: String?
    private var pollTask: Task<Void, Never>?
    private let session = URLSession.shared

    private var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUBZERO_PAIRING_WORKER_URL") as? String,
              let url = URL(string: raw), url.scheme == "https", !raw.contains("REPLACE") else { return nil }
        return url
    }

    var isConfigured: Bool { baseURL != nil }

    func beginPairing(deviceId: String, deviceName: String) {
        guard let baseURL else {
            lastError = "Set SUBZERO_PAIRING_WORKER_URL in Info.plist after deploying the Cloudflare Worker."
            return
        }
        pollTask?.cancel()
        isPaired = false
        pairingCode = nil
        pairingSecret = nil
        lastError = nil
        statusMessage = "Creating pairing code…"

        Task {
            do {
                let response: StartResponse = try await request(
                    baseURL.appending(path: "v1/pairings"),
                    method: "POST",
                    body: ["deviceId": deviceId, "deviceName": deviceName]
                )
                pairingCode = response.code
                pairingSecret = response.secret
                statusMessage = "Enter this code in the Android app within \(response.expiresInSeconds / 60) minutes."
                pollForPairing()
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Pairing unavailable"
            }
        }
    }

    func cancelPairing() {
        pollTask?.cancel()
        pairingCode = nil
        pairingSecret = nil
        isPaired = false
        pairedEmail = nil
        statusMessage = "Not paired"
    }

    func publishThermalEvent(maxTemp: Double, alertTriggered: Bool, message: String, cpuTemp: Double?, gpuTemp: Double?, cpuLoad: Double, batteryPct: Double, isCharging: Bool, packageWatts: Double?, thermalState: String, alertThreshold: Double) {
        guard isPaired, let baseURL, let pairingCode, let pairingSecret else { return }
        Task {
            do {
                let _: AcceptResponse = try await request(
                    baseURL.appending(path: "v1/telemetry"),
                    method: "POST",
                    body: ["pairingCode": pairingCode, "maxTemp": maxTemp, "alertTriggered": alertTriggered, "alertMessage": message, "cpuTemp": cpuTemp ?? 0, "gpuTemp": gpuTemp ?? 0, "cpuLoad": cpuLoad, "batteryPct": batteryPct, "isCharging": isCharging, "packageWatts": packageWatts ?? 0, "thermalState": thermalState, "alertThreshold": alertThreshold],
                    headers: ["x-subzero-pairing-secret": pairingSecret]
                )
            } catch {
                lastError = "Push delivery failed: \(error.localizedDescription)"
            }
        }
    }

    func triggerTestAlert() {
        guard isPaired, let baseURL, let pairingCode, let pairingSecret else {
            lastError = "Pair this Mac with Android before sending a test notification."
            return
        }
        Task {
            do {
                let _: AcceptResponse = try await request(
                    baseURL.appending(path: "v1/telemetry"),
                    method: "POST",
                    body: ["pairingCode": pairingCode, "maxTemp": 92.5, "alertTriggered": true, "alertMessage": "[DEMO ALERT] Critical Mac temperature (92.5°C) simulated."],
                    headers: ["x-subzero-pairing-secret": pairingSecret]
                )
                statusMessage = "Test FCM notification sent."
            } catch {
                lastError = "Test notification failed: \(error.localizedDescription)"
            }
        }
    }

    private func pollForPairing() {
        pollTask = Task {
            while !Task.isCancelled, !isPaired {
                try? await Task.sleep(for: .seconds(3))
                guard let baseURL, let pairingCode, let pairingSecret else { return }
                do {
                    let status: StatusResponse = try await request(
                        baseURL.appending(path: "v1/pairings/\(pairingCode)"),
                        method: "GET",
                        headers: ["x-subzero-pairing-secret": pairingSecret]
                    )
                    if status.status == "paired" {
                        isPaired = true
                        pairedEmail = status.userEmail
                        statusMessage = "Paired with Android\(status.userEmail.map { " (\($0))" } ?? "")."
                    }
                } catch { }
            }
        }
    }

    private func request<T: Decodable>(_ url: URL, method: String, body: [String: Any]? = nil, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIError.self, from: data)
            throw NSError(domain: "SubZeroPairing", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: apiError?.error ?? "Pairing service request failed."])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct StartResponse: Decodable { let code: String; let expiresInSeconds: Int; let secret: String }
private struct StatusResponse: Decodable { let status: String; let userEmail: String? }
private struct AcceptResponse: Decodable { let accepted: Bool }
private struct APIError: Decodable { let error: String }
