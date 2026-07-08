// Bech32 checksum implementation (BIP-0173).
//
// Vendored verbatim from age-plugin-se (~/src/age-plugin-se/Sources/Bech32.swift),
// which itself adapted https://github.com/0xDEADP00L/Bech32 (MIT, © 2018 Evolution
// Group Limited). Vendored — rather than depended on — so our Secure Enclave key
// encodings (age1se1…, AGE-PLUGIN-SE-1…) are byte-identical to age-plugin-se's.
//
// MIT License. See the header retained below.

// Copyright 2018 Evolution Group Limited
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

import Foundation

/// Bech32 checksum implementation.
final class Bech32 {
    private let gen: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
    private let checksumMarker: String = "1"
    private let encCharset: Data = Data("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
    private let decCharset: [Int8] = [
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        15, -1, 10, 17, 21, 20, 26, 30, 7, 5, -1, -1, -1, -1, -1, -1,
        -1, 29, -1, 24, 13, 25, 9, 8, 23, -1, 18, 22, 31, 27, 19, -1,
        1, 0, 3, 16, 11, 28, 12, 14, 6, 4, 2, -1, -1, -1, -1, -1,
        -1, 29, -1, 24, 13, 25, 9, 8, 23, -1, 18, 22, 31, 27, 19, -1,
        1, 0, 3, 16, 11, 28, 12, 14, 6, 4, 2, -1, -1, -1, -1, -1,
    ]

    private func convertBits(from: Int, to: Int, pad: Bool, idata: Data) throws -> Data {
        var acc: Int = 0
        var bits: Int = 0
        let maxv: Int = (1 << to) - 1
        let maxAcc: Int = (1 << (from + to - 1)) - 1
        var odata = Data()
        for ibyte in idata {
            acc = ((acc << from) | Int(ibyte)) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                odata.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits != 0 {
                odata.append(UInt8((acc << (to - bits)) & maxv))
            }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            throw DecodingError.bitsConversionFailed
        }
        return odata
    }

    private func polymod(_ values: Data) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = (chk >> 25)
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i: UInt8 in 0..<5 {
                chk ^= ((top >> i) & 1) == 0 ? 0 : gen[Int(i)]
            }
        }
        return chk
    }

    private func expandHrp(_ hrp: String) -> Data {
        let hrpBytes = Data(hrp.utf8)
        var result = Data(repeating: 0x00, count: hrpBytes.count * 2 + 1)
        for (i, c) in hrpBytes.enumerated() {
            result[i] = c >> 5
            result[i + hrpBytes.count + 1] = c & 0x1f
        }
        result[hrp.count] = 0
        return result
    }

    private func verifyChecksum(hrp: String, checksum: Data) -> Bool {
        var data = expandHrp(hrp)
        data.append(checksum)
        return polymod(data) == 1
    }

    private func createChecksum(hrp: String, values: Data) -> Data {
        var enc = expandHrp(hrp)
        enc.append(values)
        enc.append(Data(repeating: 0x00, count: 6))
        let mod: UInt32 = polymod(enc) ^ 1
        var ret: Data = Data(repeating: 0x00, count: 6)
        for i in 0..<6 {
            ret[i] = UInt8((mod >> (5 * (5 - i))) & 31)
        }
        return ret
    }

    private func encodeBech32(_ hrp: String, values: Data) -> String {
        let checksum = createChecksum(hrp: hrp, values: values)
        var combined = values
        combined.append(checksum)

        let hrpBytes = Data(hrp.utf8)
        var ret = hrpBytes
        ret.append(Data("1".utf8))
        for i in combined {
            ret.append(encCharset[Int(i)])
        }
        return String(decoding: ret, as: UTF8.self)
    }

    func decodeBech32(_ str: String) throws -> (hrp: String, checksum: Data) {
        let strBytes = Data(str.utf8)
        var lower: Bool = false
        var upper: Bool = false
        for c in strBytes {
            if c < 33 || c > 126 { throw DecodingError.nonPrintableCharacter }
            if c >= 97 && c <= 122 { lower = true }
            if c >= 65 && c <= 90 { upper = true }
        }
        if lower && upper { throw DecodingError.invalidCase }
        guard let pos = str.range(of: checksumMarker, options: .backwards)?.lowerBound else {
            throw DecodingError.noChecksumMarker
        }
        let intPos: Int = str.distance(from: str.startIndex, to: pos)
        guard intPos >= 1 else { throw DecodingError.incorrectHrpSize }
        guard intPos + 7 <= str.count else { throw DecodingError.incorrectChecksumSize }
        let vSize: Int = str.count - 1 - intPos
        var values: Data = Data(repeating: 0x00, count: vSize)
        for i in 0..<vSize {
            let c = strBytes[i + intPos + 1]
            let decInt = decCharset[Int(c)]
            if decInt == -1 { throw DecodingError.invalidCharacter }
            values[i] = UInt8(decInt)
        }
        let hrp = String(str[..<pos]).lowercased()
        guard verifyChecksum(hrp: hrp, checksum: values) else {
            throw DecodingError.checksumMismatch
        }
        return (hrp, Data(values[..<(vSize - 6)]))
    }

    func encode(hrp: String, data: Data) -> String {
        let isUpper = hrp[hrp.startIndex].isUppercase
        let result = encodeBech32(
            isUpper ? hrp.lowercased() : hrp,
            values: try! self.convertBits(from: 8, to: 5, pad: true, idata: data))
        return isUpper ? result.uppercased() : result
    }

    func decode(_ str: String) throws -> (hrp: String, data: Data) {
        let isUpper = str[str.startIndex].isUppercase
        let result = try decodeBech32(isUpper ? str.lowercased() : str)
        return (
            isUpper ? result.hrp.uppercased() : result.hrp,
            try convertBits(from: 5, to: 8, pad: false, idata: result.checksum)
        )
    }
}

extension Bech32 {
    enum DecodingError: LocalizedError {
        case nonUTF8String
        case nonPrintableCharacter
        case invalidCase
        case noChecksumMarker
        case incorrectHrpSize
        case incorrectChecksumSize
        case invalidCharacter
        case checksumMismatch
        case bitsConversionFailed

        var errorDescription: String? {
            switch self {
            case .bitsConversionFailed: return "Failed to perform bits conversion"
            case .checksumMismatch: return "Checksum doesn't match"
            case .incorrectChecksumSize: return "Checksum size too low"
            case .incorrectHrpSize: return "Human-readable-part is too small or empty"
            case .invalidCase: return "String contains mixed case characters"
            case .invalidCharacter: return "Invalid character met on decoding"
            case .noChecksumMarker: return "Checksum delimiter not found"
            case .nonPrintableCharacter: return "Non printable character in input string"
            case .nonUTF8String: return "String cannot be decoded by utf8 decoder"
            }
        }
    }
}

// MARK: - Raw (unpadded) base64 used by age stanza arguments

extension Data {
    /// Decode standard base64 without padding (age stanza arg encoding).
    init?(base64RawEncoded raw: String) {
        if raw.hasSuffix("=") { return nil }
        var str = raw
        switch raw.count % 4 {
        case 2: str += "=="
        case 3: str += "="
        default: break
        }
        guard let data = Data(base64Encoded: str) else { return nil }
        self = data
    }

    /// Encode as standard base64 without padding or line breaks.
    var base64RawEncodedString: String {
        var s = base64EncodedString()
        while s.hasSuffix("=") { s.removeLast() }
        return s
    }
}
