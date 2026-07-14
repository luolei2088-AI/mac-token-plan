import Foundation
import CryptoKit

/// 火山方舟 Agent Plan (AFP) 额度。
/// 接口：GET https://open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01
/// 认证：火山引擎 OpenAPI V4 签名（AK/SK），serviceCode=ark，region=cn-north-1。
/// 返回：5小时 / 7天 / 月度总额度 / 今日，各含 Quota/Used。
final class VolcEngineProvider: QuotaProvider {
    let id = "volcengine"
    let displayName = "火山方舟 Agent Plan"
    private let ak: String
    private let sk: String

    init(ak: String, sk: String) { self.ak = ak; self.sk = sk }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard !ak.isEmpty, !sk.isEmpty else { throw ProviderError.notConfigured }
        let (url, headers) = signedRequest(action: "GetAFPUsage", version: "2024-01-01")
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let body = try JSONDecoder().decode(VolcResponse.self, from: data)
        if let msg = body.responseMetadata?.error?.message, !msg.isEmpty {
            throw ProviderError.apiError(msg)
        }
        guard let r = body.result else { throw ProviderError.apiError("无返回数据") }
        var buckets: [QuotaBucket] = []
        if let w = r.afpFiveHour { buckets.append(.init(label: "5小时", used: w.used, limit: w.quota, percentOnly: true, resetTime: w.resetTime.map { Date(timeIntervalSince1970: $0 / 1000) })) }
        if let w = r.afpWeekly { buckets.append(.init(label: "7天", used: w.used, limit: w.quota, percentOnly: true, resetTime: w.resetTime.map { Date(timeIntervalSince1970: $0 / 1000) })) }
        if let w = r.afpMonthly { buckets.append(.init(label: "总额度", used: w.used, limit: w.quota, percentOnly: true)) }
        return buckets
    }

    // MARK: - V4 签名
    private func signedRequest(action: String, version: String) -> (URL, [String: String]) {
        let host = "open.volcengineapi.com"
        let region = "cn-north-1"
        let service = "ark"
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let xDate = String(format: "%04d%02d%02dT%02d%02d%02dZ",
                           c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        let shortDate = String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)

        let query: [(String, String)] = [("Action", action), ("Version", version)].sorted { $0.0 < $1.0 }
        let cqs = query.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
        let hp = sha256Hex("")
        let hdrs: [(String, String)] = [
            ("Host", host), ("X-Date", xDate),
            ("X-Content-Sha256", hp), ("Content-Type", "application/x-www-form-urlencoded"),
        ].sorted { $0.0.lowercased() < $1.0.lowercased() }
        let canonicalHeaders = hdrs.map { "\($0.0.lowercased()):\($0.1)\n" }.joined()
        let signedHeaders = hdrs.map { $0.0.lowercased() }.joined(separator: ";")
        let canonicalRequest = "GET\n/\n\(cqs)\n\(canonicalHeaders)\n\(signedHeaders)\n\(hp)"
        let credentialScope = "\(shortDate)/\(region)/\(service)/request"
        let stringToSign = "HMAC-SHA256\n\(xDate)\n\(credentialScope)\n\(sha256Hex(canonicalRequest))"

        let kDate = hmac(key: sk.data(using: .utf8)!, msg: shortDate)
        let kRegion = hmac(key: kDate, msg: region)
        let kService = hmac(key: kRegion, msg: service)
        let kSigning = hmac(key: kService, msg: "request")
        let signature = hmacHex(key: kSigning, msg: stringToSign)
        let auth = "HMAC-SHA256 Credential=\(ak)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        let url = URL(string: "https://\(host)/?\(cqs)")!
        return (url, ["Authorization": auth, "X-Date": xDate, "X-Content-Sha256": hp,
                      "Content-Type": "application/x-www-form-urlencoded"])
    }

    private func enc(_ s: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
    private func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: s.data(using: .utf8)!).map { String(format: "%02x", Int($0)) }.joined()
    }
    private func hmac(key: Data, msg: String) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: msg.data(using: .utf8)!, using: SymmetricKey(data: key))
        return Data(mac)
    }
    private func hmacHex(key: Data, msg: String) -> String {
        hmac(key: key, msg: msg).map { String(format: "%02x", Int($0)) }.joined()
    }
}

private struct VolcResponse: Decodable {
    let responseMetadata: ResponseMetadata?
    let result: Result?
    enum CodingKeys: String, CodingKey { case responseMetadata = "ResponseMetadata"; case result = "Result" }
    struct ResponseMetadata: Decodable {
        let error: ApiError?
        enum CodingKeys: String, CodingKey { case error = "Error" }
    }
    struct ApiError: Decodable { let code: String?; let message: String? }
    struct Result: Decodable {
        let planType: String?
        let afpDaily: Window?
        let afpFiveHour: Window?
        let afpWeekly: Window?
        let afpMonthly: Window?
        enum CodingKeys: String, CodingKey {
            case planType = "PlanType"
            case afpDaily = "AFPDaily"; case afpFiveHour = "AFPFiveHour"
            case afpWeekly = "AFPWeekly"; case afpMonthly = "AFPMonthly"
        }
    }
    struct Window: Decodable {
        let quota: Double
        let used: Double
        let resetTime: Double?
        enum CodingKeys: String, CodingKey { case quota = "Quota"; case used = "Used"; case resetTime = "ResetTime" }
    }
}
