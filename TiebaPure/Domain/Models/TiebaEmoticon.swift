import Foundation

enum TiebaEmoticon {
    private static let namesByImageName: [String: String] = [
        "image_emoticon1": "呵呵",
        "image_emoticon2": "哈哈",
        "image_emoticon3": "吐舌",
        "image_emoticon4": "啊",
        "image_emoticon5": "酷",
        "image_emoticon6": "怒",
        "image_emoticon7": "开心",
        "image_emoticon8": "汗",
        "image_emoticon9": "泪",
        "image_emoticon10": "黑线",
        "image_emoticon11": "鄙视",
        "image_emoticon12": "不高兴",
        "image_emoticon13": "真棒",
        "image_emoticon14": "钱",
        "image_emoticon15": "疑问",
        "image_emoticon16": "阴险",
        "image_emoticon17": "吐",
        "image_emoticon18": "咦",
        "image_emoticon19": "委屈",
        "image_emoticon20": "花心",
        "image_emoticon21": "呼~",
        "image_emoticon22": "笑眼",
        "image_emoticon23": "冷",
        "image_emoticon24": "太开心",
        "image_emoticon25": "滑稽",
        "image_emoticon26": "勉强",
        "image_emoticon27": "狂汗",
        "image_emoticon28": "乖",
        "image_emoticon29": "睡觉",
        "image_emoticon30": "惊哭",
        "image_emoticon31": "生气",
        "image_emoticon32": "惊讶",
        "image_emoticon33": "喷",
        "image_emoticon34": "爱心",
        "image_emoticon35": "心碎",
        "image_emoticon36": "玫瑰",
        "image_emoticon37": "礼物",
        "image_emoticon38": "彩虹",
        "image_emoticon39": "星星月亮",
        "image_emoticon40": "太阳",
        "image_emoticon41": "钱币",
        "image_emoticon42": "灯泡",
        "image_emoticon43": "茶杯",
        "image_emoticon44": "蛋糕",
        "image_emoticon45": "音乐",
        "image_emoticon46": "haha",
        "image_emoticon47": "胜利",
        "image_emoticon48": "大拇指",
        "image_emoticon49": "弱",
        "image_emoticon50": "OK",
        "image_emoticon77": "沙发",
        "image_emoticon78": "手纸",
        "image_emoticon79": "香蕉",
        "image_emoticon80": "便便",
        "image_emoticon81": "药丸",
        "image_emoticon82": "红领巾",
        "image_emoticon83": "蜡烛",
        "image_emoticon84": "三道杠",
        "image_emoticon89": "噗"
    ]

    private static let imageNamesByName: [String: String] = {
        var result: [String: String] = [:]
        for (imageName, name) in namesByImageName {
            result[name] = imageName
        }
        result["呵"] = "image_emoticon1"
        result["笑"] = "image_emoticon2"
        result["大笑"] = "image_emoticon2"
        result["高兴"] = "image_emoticon7"
        result["笑脸"] = "image_emoticon7"
        result["黑头"] = "image_emoticon10"
        result["黑脸"] = "image_emoticon10"
        result["黑头高兴"] = "image_emoticon7"
        result["黑头开心"] = "image_emoticon7"
        result["黑头笑"] = "image_emoticon2"
        for (imageName, name) in namesByImageName {
            result["小\(name)"] = imageName
        }
        return result
    }()

    private static let tokenExpression = try? NSRegularExpression(
        pattern: #"#\(([^)]+)\)|\(#([^)]+)\)|\[([^\]\n]{1,12})\]"#,
        options: []
    )

    static func normalizedName(from code: String) -> String {
        var value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#("), value.hasSuffix(")") {
            value.removeFirst(2)
            value.removeLast()
        } else if value.hasPrefix("(#"), value.hasSuffix(")") {
            value.removeFirst(2)
            value.removeLast()
        } else if value.hasPrefix("["), value.hasSuffix("]") {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    static func imageName(for code: String) -> String? {
        let normalized = normalizedName(from: code)
        if namesByImageName[normalized] != nil {
            return normalized
        }
        if normalized == "image_emoticon" {
            return "image_emoticon1"
        }
        if isImageName(normalized) {
            return normalized
        }
        return imageNamesByName[normalized]
    }

    static func imageURL(for code: String) -> URL? {
        guard let imageName = imageName(for: code) else { return nil }
        return Bundle.main.url(forResource: imageName, withExtension: "webp", subdirectory: "Emoticons")
            ?? Bundle.main.url(forResource: imageName, withExtension: "webp")
            ?? Bundle.main.url(forResource: imageName, withExtension: "png", subdirectory: "Emoticons")
            ?? Bundle.main.url(forResource: imageName, withExtension: "png")
    }

    static func displayText(for code: String) -> String {
        let normalized = normalizedName(from: code)
        return "[\(namesByImageName[normalized] ?? normalized)]"
    }

    static func plainDisplayText(_ text: String) -> String {
        replaceTokens(in: text) { displayText(for: $0) }
    }

    static func blocks(from text: String) -> [ContentBlock] {
        guard text.isEmpty == false, let expression = tokenExpression else { return [] }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard matches.isEmpty == false else { return [.text(text)] }

        var blocks: [ContentBlock] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let range = NSRange(location: cursor, length: match.range.location - cursor)
                let value = nsText.substring(with: range)
                if value.isEmpty == false {
                    blocks.append(.text(value))
                }
            }

            if let token = token(in: match, text: nsText) {
                if token.requiresKnownImage, imageName(for: token.name) == nil {
                    blocks.append(.text(nsText.substring(with: match.range)))
                } else {
                    blocks.append(.emoticon(code: token.name))
                }
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            let value = nsText.substring(from: cursor)
            if value.isEmpty == false {
                blocks.append(.text(value))
            }
        }
        return blocks
    }

    private static func replaceTokens(in text: String, replacement: (String) -> String) -> String {
        guard text.isEmpty == false, let expression = tokenExpression else { return text }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard matches.isEmpty == false else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let range = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(nsText.substring(with: range))
            }
            if let token = token(in: match, text: nsText) {
                if token.requiresKnownImage, imageName(for: token.name) == nil {
                    result.append(nsText.substring(with: match.range))
                } else {
                    result.append(replacement(token.name))
                }
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            result.append(nsText.substring(from: cursor))
        }
        return result
    }

    private static func token(in match: NSTextCheckingResult, text: NSString) -> (name: String, requiresKnownImage: Bool)? {
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { continue }
            let name = text.substring(with: range)
            return (name, index == 3)
        }
        return nil
    }

    private static func isImageName(_ value: String) -> Bool {
        guard value.hasPrefix("image_emoticon") else { return false }
        let suffix = value.dropFirst("image_emoticon".count)
        return suffix.isEmpty == false && suffix.allSatisfy(\.isNumber)
    }
}
