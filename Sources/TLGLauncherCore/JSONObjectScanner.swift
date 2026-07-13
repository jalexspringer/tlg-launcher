import Foundation

/// Splits a JSON file into its top-level `{…}` objects with 1-based line
/// ranges — a faithful port of `breakJSONIntoSingleObjects` from
/// RenechCDDA/tlg-data's pull-data.mjs, so locally generated guide data
/// carries identical `__filename … #L<start>-L<end>` source links.
///
/// Operates on bytes: every character it inspects is ASCII, so UTF-8
/// multi-byte sequences pass through unharmed.
public enum JSONObjectScanner {
    public struct ScannedObject: Sendable {
        public let bytes: Data
        public let startLine: Int
        public let endLine: Int
    }

    public static func topLevelObjects(in data: Data) -> [ScannedObject] {
        var objects: [ScannedObject] = []
        var depth = 0
        var line = 1
        var start = -1
        var startLine = -1
        var inString = false
        var inEscape = false

        for (index, byte) in data.enumerated() {
            if inString {
                if inEscape {
                    inEscape = false
                } else if byte == UInt8(ascii: "\\") {
                    inEscape = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else {
                switch byte {
                case UInt8(ascii: "{"):
                    if depth == 0 {
                        start = index
                        startLine = line
                    }
                    depth += 1
                case UInt8(ascii: "}"):
                    depth -= 1
                    if depth == 0 {
                        objects.append(ScannedObject(
                            bytes: data.subdata(in: data.startIndex + start ..< data.startIndex + index + 1),
                            startLine: startLine,
                            endLine: line
                        ))
                    }
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "\n"):
                    line += 1
                default:
                    break
                }
            }
        }
        return objects
    }
}
