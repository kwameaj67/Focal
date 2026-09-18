//
//  OutputDirectory.swift
//  CameraSDKCore
//
//  Resolves the directory where recorded/imported media is written, creating a
//  dedicated subfolder in the system temp directory when the host doesn't
//  supply one.
//

import Foundation

package enum OutputDirectory {

    /// Returns the host-supplied directory, or a created `CameraSDK` temp
    /// folder. Always returns a directory that exists.
    package static func resolve(_ requested: URL?) -> URL {
        if let requested {
            try? FileManager.default.createDirectory(
                at: requested, withIntermediateDirectories: true
            )
            return requested
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraSDK", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: temp, withIntermediateDirectories: true
        )
        return temp
    }
}
