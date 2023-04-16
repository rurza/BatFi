#!/usr/bin/env xcrun --sdk macosx swift
//
//  PropertyListModifier.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-23
//

// This script generates all of the property list requirements needed by SMJobBless and XPC Mach Services in conjunction
// with user defined variables specified in the xcconfig files. This scripts adds/modifies/removes entries to:
//  - App's info property list
//  - Helper tool's info property list
//  - Helper tool's launchd property list
//
// For this sample, this script is run both at the beginning and end of the build process for both targets. When run at
// the end it deletes all of the property list requirement changes it applied. For your own project you may not find it
// useful to do this cleanup task at the end of the build process.
//
// Additionally this script can auto-increment the helper tools's version number whenever the source code changes
//  - SMJobBless will only successfully install a new helper tool over an existing one if its version is greater
//  - In order to track changes, a BuildHash entry will be added to the helper tool's Info property list
//  - This sample is configured by default to perform this auto-increment
//
// All of these options are configured by passing in command line arguments to this script. See ScriptTask for details.

import Foundation
import CryptoKit

/// Errors raised throughout this script.
enum ScriptError: Error {
    case general(String)
    case wrapped(String, Error)
}

// MARK: helper functions to read environment variables

/// Attempts to read an environment variable, throws an error if it is not present.
///
/// - Parameters:
///   - name: Name of the environment variable.
///   - description: A description of what was trying to be read; used in the error message if one is thrown.
///   - isUserDefined: Whether the environment variable is user defined; used to modify the error message if one is thrown.
func readEnvironmentVariable(name: String, description: String, isUserDefined: Bool) throws -> String {
    if let value = ProcessInfo.processInfo.environment[name] {
        return value
    } else {
        var message = "Unable to determine \(description), missing \(name) environment variable."
        if isUserDefined {
            message += " This is a user-defined variable. Please check that the xcconfig files are present and " +
            "configured in the project settings."
        }
        throw ScriptError.general(message)
    }
}

/// Attempts to read an environment variable as a URL.
func readEnvironmentVariableAsURL(name: String, description: String, isUserDefined: Bool) throws -> URL {
    let value = try readEnvironmentVariable(name: name, description: description, isUserDefined: isUserDefined)
    
    return URL(fileURLWithPath: value)
}

// MARK: property list keys

// Helper tool - info
/// Key for entry in helper tool's info property list.
let SMAuthorizedClientsKey = "SMAuthorizedClients"
/// Key for bundle identifier.
let CFBundleIdentifierKey = kCFBundleIdentifierKey as String
/// Key for bundle version.
let CFBundleVersionKey = kCFBundleVersionKey as String
/// Custom key for an entry in the helper tool's info plist that contains a hash of source files. Used to detect when the build changes.
let BuildHashKey = "BuildHash"

// Helper tool - launchd
/// Key for entry in helper tool's launchd property list.
let LabelKey = "Label"
/// Key for XPC mach service used by the helper tool.
let MachServicesKey = "MachServices"

let BundleProgramKey = "BundleProgram"

// App - info
/// Key for entry in app's info property list.
let SMPrivilegedExecutablesKey = "SMPrivilegedExecutables"

// MARK: code signing requirements

/// A requirement that the organizational unit for the leaf certificate match the development team identifier.
///
/// From Apple's documentation: "In Apple issued developer certificates, this field contains the developer’s Team Identifier."
///
/// The leaf certificate is the one which corresponds to your developer certificate. The certificates above it in the chain are Apple's.
/// Depending on whether this build is signed for debug or release the leaf certificate *will* differ, but the organizational unit, represented by `subject.OU` in
/// the function, will remain the same.
func organizationalUnitRequirement() throws -> String {
    // In order for this requirement to actually work, the signed app or helper tool needs to have a certificate chain
    // which will contain the organizational unit (subject.OU). While it'd be great if we could just examine the signed
    // app/helper tool after that's been done, that's of course not possible as we need to generate this requirement
    // *during* the process for each.
    //
    // Note: In practice this certificate chain won't exist when self signing using "Sign to Run Locally".
    //
    // There's no to precise way to determine if the subject.OU will be present, but in practice we can check for the
    // subject.CN (CN stands for common name) by seeing if there is a meaningful value for the CODE_SIGN_IDENTITY
    // build variable. This could still fail because we're checking for *this* target's common name, but creating an
    // identity for the *other* target - so if Xcode isn't configured the same for both targets an issue is likely to
    // arise.
    //
    // Note: The reason to use the organizational unit for the code requirement instead of the common name is because
    // the organizational unit will be consistent between the Apple Development and Developer ID builds, while the
    // common name will not be — simplifying the development workflow.
    let commonName = ProcessInfo.processInfo.environment["CODE_SIGN_IDENTITY"]
    if commonName == nil || commonName == "-" {
        throw ScriptError.general("Signing Certificate must be Development. Sign to Run Locally is not supported.")
    }
    
    let developmentTeamId = try readEnvironmentVariable(name: "DEVELOPMENT_TEAM",
                                                        description: "development team for code signing",
                                                        isUserDefined: false)
    guard developmentTeamId.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
        if developmentTeamId == "-" {
            throw ScriptError.general("Development Team for code signing is not set")
        } else {
            throw ScriptError.general("Development Team for code signing is invalid: \(developmentTeamId)")
        }
    }
    let certificateString = "certificate leaf[subject.OU] = \"\(developmentTeamId)\""
    
    return certificateString
}

/// Requirement that Apple is part of the certificate chain, mean it was signed by an Apple issued certificate
let appleGenericRequirement = "anchor apple generic"

/// Creates a `SMAuthorizedClients` entry representing the app which must go inside the helper tool's info property list.
func SMAuthorizedClientsEntry() throws -> (key: String, value: [String]) {
    let appIdentifierRequirement = "identifier \"\(try TargetType.app.bundleIdentifier())\""
    // Create requirement that the app must be its current version or later. This mitigates downgrade attacks where an
    // older version of the app had a security vulnerability fixed in later versions. The attacker could then
    // intentionally install and run an older version of the app and exploit its vulnerability in order to talk to
    // the helper tool.
    let appVersion = try readEnvironmentVariable(name: "APP_VERSION",
                                                 description: "app version",
                                                 isUserDefined: true)
    let appVersionRequirement = "info[\(CFBundleVersionKey)] >= \"\(appVersion)\""
    let requirements = [appleGenericRequirement,
                        appIdentifierRequirement,
                        appVersionRequirement,
                        try organizationalUnitRequirement()]
    let value = [requirements.joined(separator: " and ")]
    
    return (SMAuthorizedClientsKey, value)
}

/// Creates a `SMPrivilegedExecutables` entry representing the helper tool which must go inside the app's info property list.
func SMPrivilegedExecutablesEntry() throws -> (key: String, value: [String : String]) {
    let helperToolIdentifierRequirement = "identifier \"\(try TargetType.helperTool.bundleIdentifier())\""
    let requirements = [appleGenericRequirement, helperToolIdentifierRequirement, try organizationalUnitRequirement()]
    let value = [try TargetType.helperTool.bundleIdentifier() : requirements.joined(separator: " and ")]
    
    return (SMPrivilegedExecutablesKey, value)
}

/// Creates a `Label` entry which must go inside the helper tool's launchd property list.
func LabelEntry() throws -> (key: String, value: String) {
    return (key: LabelKey, value: try TargetType.helperTool.bundleIdentifier())
}

// MARK: property list manipulation

/// Reads the property list at the provided path.
///
/// - Parameters:
///   - atPath: Where the property list is located.
/// - Returns: Tuple containing entries and the format of the on disk property list.
func readPropertyList(atPath path: URL) throws -> (entries: NSMutableDictionary,
                                                   format: PropertyListSerialization.PropertyListFormat) {
    let onDiskPlistData: Data
    do {
        onDiskPlistData = try Data(contentsOf: path)
    } catch {
        throw ScriptError.wrapped("Unable to read property list at: \(path)", error)
    }
    
    do {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: onDiskPlistData,
                                                               options: .mutableContainersAndLeaves,
                                                               format: &format)
        if let entries = plist as? NSMutableDictionary {
            return (entries: entries, format: format)
        }
        else {
            throw ScriptError.general("Unable to cast parsed property list")
        }
    }
    catch {
        throw ScriptError.wrapped("Unable to parse property list", error)
    }
}

/// Writes (or overwrites) a property list at the provided path.
///
/// - Parameters:
///   - atPath: Where the property list should be written.
///   - entries: All entries to be written to the property list, this does not append - it overwrites anything existing.
///   - format:The format to use when writing entries to `atPath`.
func writePropertyList(atPath path: URL,
                       entries: NSDictionary,
                       format: PropertyListSerialization.PropertyListFormat) throws {
    let plistData: Data
    do {
        plistData = try PropertyListSerialization.data(fromPropertyList: entries,
                                                       format: format,
                                                       options: 0)
    } catch {
        throw ScriptError.wrapped("Unable to serialize property list in order to write to path: \(path)", error)
    }
    
    do {
        try plistData.write(to: path)
    }
    catch {
        throw ScriptError.wrapped("Unable to write property list to path: \(path)", error)
    }
}

/// Updates the property list with the provided entries.
///
/// If an existing entry exists for the given key it will be overwritten. If the property file does not exist, it will be created.
func updatePropertyListWithEntries(_ newEntries: [String : AnyHashable], atPath path: URL) throws {
    let (entries, format) : (NSMutableDictionary, PropertyListSerialization.PropertyListFormat)
    if FileManager.default.fileExists(atPath: path.path) {
        (entries, format) = try readPropertyList(atPath: path)
    } else {
        (entries, format) = ([:], PropertyListSerialization.PropertyListFormat.xml)
    }
    for (key, value) in newEntries {
        entries.setValue(value, forKey: key)
    }
    try writePropertyList(atPath: path, entries: entries, format: format)
}

/// Updates the property list by removing the provided keys (if present) or deletes the file if there are now no entries.
func removePropertyListEntries(forKeys keys: [String], atPath path: URL) throws {
    let (entries, format) = try readPropertyList(atPath: path)
    for key in keys {
        entries.removeObject(forKey: key)
    }
    
    if entries.count > 0 {
        try writePropertyList(atPath: path, entries: entries, format: format)
    } else {
        try FileManager.default.removeItem(at: path)
    }
}

/// The path of the info property list for this target.
func infoPropertyListPath() throws -> URL {
    return try readEnvironmentVariableAsURL(name: "INFOPLIST_FILE",
                                            description: "info property list path",
                                            isUserDefined: true)
}

/// The path of the launchd property list for the helper tool.
func launchdPropertyListPath() throws -> URL {
    try readEnvironmentVariableAsURL(name: "LAUNCHDPLIST_FILE",
                                     description: "launchd property list path",
                                     isUserDefined: true)
}

// MARK: automatic bundle version updating

/// Hashes Swift source files in the helper tool's directory as well as the shared directory.
///
/// - Returns: hash value, hex encoded
func hashSources() throws -> String {
    // Directories to hash source files in
    let sourcePaths: [URL] = [
        try infoPropertyListPath().deletingLastPathComponent(),
        try readEnvironmentVariableAsURL(name: "SHARED_DIRECTORY",
                                         description: "shared source directory path",
                                         isUserDefined: true)
    ]
    
    // Enumerate over and hash Swift source files
    var sha256 = SHA256()
    for sourcePath in sourcePaths {
        if let enumerator = FileManager.default.enumerator(at: sourcePath, includingPropertiesForKeys: []) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    do {
                        sha256.update(data: try Data(contentsOf: fileURL))
                    } catch {
                        throw ScriptError.wrapped("Unable to hash \(fileURL)", error)
                    }
                }
            }
        } else {
            throw ScriptError.general("Could not create enumerator for: \(sourcePath)")
        }
    }
    let digestHex = sha256.finalize().compactMap{ String(format: "%02x", $0) }.joined()
    
    return digestHex
}

/// Represents the value corresponding to the key `CFBundleVersionKey` in the info property list.
enum BundleVersion {
    case major(UInt)
    case majorMinor(UInt, UInt)
    case majorMinorPatch(UInt, UInt, UInt)
    
    init?(version: String) {
        let versionParts = version.split(separator: ".")
        if versionParts.count == 1,
           let major = UInt(versionParts[0]) {
            self = .major(major)
        }
        else if versionParts.count == 2,
                let major = UInt(versionParts[0]),
                let minor = UInt(versionParts[1]) {
            self = .majorMinor(major, minor)
        }
        else if versionParts.count == 3,
                let major = UInt(versionParts[0]),
                let minor = UInt(versionParts[1]),
                let patch = UInt(versionParts[2]) {
            self = .majorMinorPatch(major, minor, patch)
        }
        else {
            return nil
        }
    }
    
    var version: String {
        switch self {
        case .major(let major):
            return "\(major)"
        case .majorMinor(let major, let minor):
            return "\(major).\(minor)"
        case .majorMinorPatch(let major, let minor, let patch):
            return "\(major).\(minor).\(patch)"
        }
    }
    
    func increment() -> BundleVersion {
        switch self {
        case .major(let major):
            return .major(major + 1)
        case .majorMinor(let major, let minor):
            return .majorMinor(major, minor + 1)
        case .majorMinorPatch(let major, let minor, let patch):
            return .majorMinorPatch(major, minor, patch + 1)
        }
    }
}

/// Reads the `CFBundleVersion` value from the passed in dictionary.
func readBundleVersion(propertyList: NSMutableDictionary) throws -> BundleVersion {
    if let value = propertyList[CFBundleVersionKey] as? String {
        if let version = BundleVersion(version: value) {
            return version
        } else {
            throw ScriptError.general("Invalid value for \(CFBundleVersionKey) in property list")
        }
    } else {
        throw ScriptError.general("Could not find version, \(CFBundleVersionKey) missing in property list")
    }
}

/// Reads the `BuildHash` value from the passed in dictionary.
func readBuildHash(propertyList: NSMutableDictionary) throws -> String? {
    return propertyList[BuildHashKey] as? String
}

/// Reads the info property list, determines if the build has changed based on stored hash values, and increments the build version if it has.
func incrementBundleVersionIfNeeded(infoPropertyListPath: URL) throws {
    let propertyList = try readPropertyList(atPath: infoPropertyListPath)
    let previousBuildHash = try readBuildHash(propertyList: propertyList.entries)
    let currentBuildHash = try hashSources()
    if currentBuildHash != previousBuildHash {
        let version = try readBundleVersion(propertyList: propertyList.entries)
        let newVersion = version.increment()
        
        propertyList.entries[BuildHashKey] = currentBuildHash
        propertyList.entries[CFBundleVersionKey] = newVersion.version
        
        try writePropertyList(atPath: infoPropertyListPath,
                              entries: propertyList.entries,
                              format: propertyList.format)
    }
}

// MARK: Xcode target

/// The two build targets used as part of this sample.
enum TargetType: String {
    case app = "APP_BUNDLE_IDENTIFIER"
    case helperTool = "HELPER_TOOL_BUNDLE_IDENTIFIER"
    
    func bundleIdentifier() throws -> String {
        return try readEnvironmentVariable(name: self.rawValue,
                                           description: "bundle identifier for \(self)",
                                           isUserDefined: true)
    }
}

/// Determines whether this script is running for the app or the helper tool.
func determineTargetType() throws -> TargetType {
    let bundleId = try readEnvironmentVariable(name: "PRODUCT_BUNDLE_IDENTIFIER",
                                               description: "bundle id",
                                               isUserDefined: false)
    
    let appBundleIdentifier = try TargetType.app.bundleIdentifier()
    let helperToolBundleIdentifier = try TargetType.helperTool.bundleIdentifier()
    if bundleId == appBundleIdentifier {
        return TargetType.app
    } else if bundleId ==  helperToolBundleIdentifier {
        return TargetType.helperTool
    } else {
        throw ScriptError.general("Unexpected bundle id \(bundleId) encountered. This means you need to update the " +
                                  "user defined variables APP_BUNDLE_IDENTIFIER and/or " +
                                  "HELPER_TOOL_BUNDLE_IDENTIFIER in Config.xcconfig.")
    }
}

// MARK: tasks

/// The tasks this script can perform. They're provided as command line arguments to this script.
typealias ScriptTask = () throws -> Void
let scriptTasks: [String : ScriptTask] = [
    /// Update the property lists as needed to satisfy the requirements of SMJobBless
    "satisfy-job-bless-requirements" : satisfyJobBlessRequirements,
    /// Clean up changes made to property lists to satisfy the requirements of SMJobBless
    "cleanup-job-bless-requirements" : cleanupJobBlessRequirements,
    /// Specifies MachServices entry in the helper tool's launchd property list to enable XPC
    "specify-mach-services" : specifyMachServices,
    /// Cleans up changes made to Mach Services in the helper tool's launchd property list
    "cleanup-mach-services" : cleanupMachServices,
    /// Auto increment the bundle version number; only intended for the helper tool.
    "auto-increment-version" : autoIncrementVersion
]

/// Determines what tasks this script should undertake in based on passed in arguments.
func determineScriptTasks() throws -> [ScriptTask] {
    if CommandLine.arguments.count > 1 {
        var matchingTasks = [ScriptTask]()
        for index in 1..<CommandLine.arguments.count {
            let arg = CommandLine.arguments[index]
            if let task = scriptTasks[arg] {
                matchingTasks.append(task)
            } else {
                throw ScriptError.general("Unexpected value provided as argument to script: \(arg)")
            }
        }
        return matchingTasks
    } else {
        throw ScriptError.general("No value(s) provided as argument to script")
    }
}

/// Updates the property lists for the app or helper tool to satisfy SMJobBless requirements.
func satisfyJobBlessRequirements() throws {
    let target = try determineTargetType()
    let infoPropertyList = try infoPropertyListPath()
    switch target {
    case .helperTool:
        let clients = try SMAuthorizedClientsEntry()
        let infoEntries: [String : AnyHashable] = [CFBundleIdentifierKey : try target.bundleIdentifier(),
                                                   clients.key : clients.value]
        try updatePropertyListWithEntries(infoEntries, atPath: infoPropertyList)
    case .app:
        let executables = try SMPrivilegedExecutablesEntry()
        try updatePropertyListWithEntries([executables.key : executables.value], atPath: infoPropertyList)

        let launchdPropertyList = try launchdPropertyListPath()
        let label = try LabelEntry()
        try updatePropertyListWithEntries([label.key : label.value], atPath: launchdPropertyList)
        let helperName = try readEnvironmentVariable(
            name: "HELPER_NAME",
            description: "helper name",
            isUserDefined: true
        )
        try updatePropertyListWithEntries(
            [
                BundleProgramKey : "Contents/MacOS/" + helperName
            ],
            atPath: launchdPropertyList
        )
    }
}

/// Removes the requirements from property lists needed to satisfy SMJobBless requirements.
func cleanupJobBlessRequirements() throws {
    let target = try determineTargetType()
    let infoPropertyList = try infoPropertyListPath()
    switch target {
    case .helperTool:
        try removePropertyListEntries(forKeys: [SMAuthorizedClientsKey, CFBundleIdentifierKey],
                                      atPath: infoPropertyList)
    case .app:
        try removePropertyListEntries(forKeys: [SMPrivilegedExecutablesKey], atPath: infoPropertyList)

        let launchdPropertyList = try launchdPropertyListPath()
        try FileManager.default.removeItem(at: launchdPropertyList)
    }
}

/// Creates a MachServices entry for the app, fails if called for the tool.
func specifyMachServices() throws {
    let target = try determineTargetType()
    switch target {
    case .helperTool:
        throw ScriptError.general("specify-mach-services only available for the app")
    case .app:
        let services = [MachServicesKey: [try TargetType.helperTool.bundleIdentifier() : true]]
        try updatePropertyListWithEntries(services, atPath: try launchdPropertyListPath())
    }
}

/// Removes a MachServices entry for the app, fails if called for the tool.
func cleanupMachServices() throws {
    let target = try determineTargetType()
    switch target {
    case .helperTool:
        throw ScriptError.general("cleanup-mach-services only available for the app")
    case .app:
        try removePropertyListEntries(forKeys: [MachServicesKey], atPath: try launchdPropertyListPath())
    }
}

/// Increments the helper tool's version, fails if called for the app.
func autoIncrementVersion() throws {
    let target = try determineTargetType()
    switch target {
    case .helperTool:
        let infoPropertyList = try infoPropertyListPath()
        try incrementBundleVersionIfNeeded(infoPropertyListPath: infoPropertyList)
    case .app:
        throw ScriptError.general("auto-increment-version only available for helper tool")
    }
}

// MARK: script starts here

do {
    for task in try determineScriptTasks() {
        try task()
    }
}
catch ScriptError.general(let message) {
    print("error: \(message)")
    exit(1)
}
catch ScriptError.wrapped(let message, let wrappedError) {
    print("error: \(message)")
    print("internal error: \(wrappedError)")
    exit(2)
}
