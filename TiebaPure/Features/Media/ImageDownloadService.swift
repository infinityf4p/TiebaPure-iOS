import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

struct TiebaImageDownloadPayload: Sendable, Equatable {
    let data: Data
    let mimeType: String
    let fileName: String
}

enum TiebaImageDownloadError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case badStatus(Int)
    case invalidImageData
    case photoLibraryAccessDenied
    case photoLibraryWriteFailed
}

struct TiebaImageDownloadClient: Sendable {
    let session: URLSession

    init(session: URLSession = TiebaImageDownloadClient.makeSession()) {
        self.session = session
    }

    func download(from url: URL) async throws -> TiebaImageDownloadPayload {
        guard TiebaURL.image(url.absoluteString) != nil else {
            throw TiebaImageDownloadError.invalidURL
        }

        var request = TiebaImageRequestPolicy.request(for: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await BoundedURLSession(session: session).data(
            for: request,
            maximumBytes: TiebaImagePipeline.maximumImageBytes,
            requiredMIMEPrefix: "image/"
        )
        guard let response = response as? HTTPURLResponse else {
            throw TiebaImageDownloadError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw TiebaImageDownloadError.badStatus(response.statusCode)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              TiebaImageDownloadPolicy.allows(source: source) else {
            throw TiebaImageDownloadError.invalidImageData
        }

        let mimeType = response.mimeType?.lowercased() ?? "image/jpeg"
        let typeIdentifier = CGImageSourceGetType(source) as String?
        return TiebaImageDownloadPayload(
            data: data,
            mimeType: mimeType,
            fileName: TiebaImageDownloadPolicy.fileName(
                for: url,
                mimeType: mimeType,
                typeIdentifier: typeIdentifier
            )
        )
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return SecureRemoteURLSession.make(
            configuration: configuration,
            redirectScope: .publicHTTPS
        )
    }
}

enum TiebaImageDownloadPolicy {
    static let maximumFileNameStemLength = 96
    static let maximumFileNameStemBytes = 180

    static func preferredURL(original: URL?, thumbnail: URL?) -> URL? {
        for candidate in [original, thumbnail].compactMap({ $0 }) {
            if let safeURL = TiebaURL.image(candidate.absoluteString) {
                return safeURL
            }
        }
        return nil
    }

    static func allows(source: CGImageSource) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return false
        }
        return TiebaImageDecodePolicy.allows(width: width, height: height)
    }

    static func fileName(
        for url: URL,
        mimeType: String,
        typeIdentifier: String?
    ) -> String {
        let rawStem = url.deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedStem = String(rawStem.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let stem = boundedStem(sanitizedStem)
        let resolvedStem = stem.isEmpty ? "TiebaPure-\(UUID().uuidString)" : stem
        return "\(resolvedStem).\(fileExtension(mimeType: mimeType, typeIdentifier: typeIdentifier))"
    }

    private static func boundedStem(_ value: String) -> String {
        var result = ""
        for character in value.prefix(maximumFileNameStemLength) {
            let next = String(character)
            guard result.utf8.count + next.utf8.count <= maximumFileNameStemBytes else { break }
            result.append(character)
        }
        return result
    }

    private static func fileExtension(mimeType: String, typeIdentifier: String?) -> String {
        if let typeIdentifier,
           let value = UTType(typeIdentifier)?.preferredFilenameExtension,
           value.isEmpty == false {
            return value.lowercased()
        }
        switch mimeType.lowercased() {
        case "image/gif": return "gif"
        case "image/png": return "png"
        case "image/heic", "image/heif": return "heic"
        case "image/webp": return "webp"
        default: return "jpg"
        }
    }
}

enum TiebaPhotoLibrarySaver {
    static func save(_ payload: TiebaImageDownloadPayload) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw TiebaImageDownloadError.photoLibraryAccessDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = payload.fileName
                request.addResource(with: .photo, data: payload.data, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? TiebaImageDownloadError.photoLibraryWriteFailed)
                }
            }
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
