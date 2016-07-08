//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CoreFoundation
import Darwin

/// Describes an error that provides localized messages describing why
/// an error occurred and provides more information about the error.
public protocol LocalizedError : ErrorProtocol {
  /// A localized message describing what error occurred.
  var errorDescription: String? { get }

  /// A localized message describing the reason for the failure.
  var failureReason: String? { get }

  /// A localized message describing how one might recover from the failure.
  var recoverySuggestion: String? { get }

  /// A localized message providing "help" text if the user requests help.
  var helpAnchor: String? { get }
}

public extension LocalizedError {
  var errorDescription: String? { return nil }
  var failureReason: String? { return nil }
  var recoverySuggestion: String? { return nil }
  var helpAnchor: String? { return nil }
}

@_silgen_name("NS_Swift_performErrorRecoverySelector")
internal func NS_Swift_performErrorRecoverySelector(
  delegate: AnyObject?,
  selector: Selector,
  success: ObjCBool,
  contextInfo: UnsafeMutablePointer<Void>?)

/// Class that implements the informal protocol
/// NSErrorRecoveryAttempting, which is used by NSError when it
/// attempts recovery from an error.
class _NSErrorRecoveryAttempter {
  // FIXME: If we could meaningfully cast the nsError back to RecoverableError,
  // we wouldn't need to capture this and could use the user-info
  // domain providers even for recoverable errors.
  let error: RecoverableError

  init(error: RecoverableError) {
    self.error = error
  }

  @objc(attemptRecoveryFromError:optionIndex:delegate:didRecoverSelector:contextInfo:)
  func attemptRecovery(fromError nsError: NSError,
                       optionIndex recoveryOptionIndex: Int,
                       delegate: AnyObject?,
                       didRecoverSelector: Selector,
                       contextInfo: UnsafeMutablePointer<Void>?) {
    error.attemptRecovery(optionIndex: recoveryOptionIndex) { success in
      NS_Swift_performErrorRecoverySelector(
        delegate: delegate,
        selector: didRecoverSelector,
        success: ObjCBool(success),
        contextInfo: contextInfo)
    }
  }

  @objc(attemptRecoveryFromError:optionIndex:)
  func attemptRecovery(fromError nsError: NSError,
                       optionIndex recoveryOptionIndex: Int) -> Bool {
    return error.attemptRecovery(optionIndex: recoveryOptionIndex)
  }
}

/// Describes an error that may be recoverably by presenting several
/// potential recovery options to the user.
public protocol RecoverableError : ErrorProtocol {
  /// Provides a set of possible recovery options to present to the user.
  var recoveryOptions: [String] { get }

  /// Attempt to recover from this error when the user selected the
  /// option at the given index. This routine must call resultHandler and
  /// indicate whether recovery was successful (or not).
  ///
  /// This entry point is used for recovery of errors handled at a
  /// "document" granularity, that do not affect the entire
  /// application.
  func attemptRecovery(optionIndex recoveryOptionIndex: Int,
                       andThen resultHandler: (recovered: Bool) -> Void)

  /// Attempt to recover from this error when the user selected the
  /// option at the given index. Returns true to indicate
  /// successful recovery, and false otherwise.
  ///
  /// This entry point is used for recovery of errors handled at
  /// the "application" granularity, where nothing else in the
  /// application can proceed until the attmpted error recovery
  /// completes.
  func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool
}

public extension RecoverableError {
  /// By default, implements document-modal recovery via application-model
  /// recovery.
  func attemptRecovery(optionIndex recoveryOptionIndex: Int,
                       andThen resultHandler: (recovered: Bool) -> Void) {
    resultHandler(recovered: attemptRecovery(optionIndex: recoveryOptionIndex))
  }
}

/// Describes an error type that specifically provides a domain, code,
/// and user-info dictionary.
public protocol CustomNSError : ErrorProtocol {
  /// The domain of the error.
  var errorDomain: String { get }

  /// The error code within the given domain.
  var errorCode: Int { get }

  /// The user-info dictionary.
  var errorUserInfo: [String : AnyObject] { get }
}

public extension ErrorProtocol where Self : CustomNSError {
  /// Default implementation for customized NSErrors.
  var _domain: String { return self.errorDomain }

  /// Default implementation for customized NSErrors.
  var _code: Int { return self.errorCode }
}

public extension ErrorProtocol {
  /// Retrieve the localized description for this error.
  var localizedDescription: String {
    return (self as! NSError).localizedDescription
  }
}

/// Retrieve the default userInfo dictionary for a given error.
@_silgen_name("swift_Foundation_getErrorDefaultUserInfo")
public func _swift_Foundation_getErrorDefaultUserInfo(_ error: ErrorProtocol)
  -> AnyObject? {
  // If the OS supports value user info value providers, use those
  // to lazily populate the user-info dictionary for this domain.
  if #available(OSX 10.11, iOS 9.0, tvOS 9.0, watchOS 2.0, *) {
    // FIXME: This is not implementable until we can recover the
    // original error from an NSError.
  }

  // Populate the user-info dictionary 
  var result: [String : AnyObject]

  // Initialize with custom user-info.
  if let customNSError = error as? CustomNSError {
    result = customNSError.errorUserInfo
  } else {
    result = [:]
  }

  if let localizedError = error as? LocalizedError {
    if let description = localizedError.errorDescription {
      result[NSLocalizedDescriptionKey] = description as AnyObject
    }
    
    if let reason = localizedError.failureReason {
      result[NSLocalizedFailureReasonErrorKey] = reason as AnyObject
    }
    
    if let suggestion = localizedError.recoverySuggestion {   
      result[NSLocalizedRecoverySuggestionErrorKey] = suggestion as AnyObject
    }
    
    if let helpAnchor = localizedError.helpAnchor {   
      result[NSHelpAnchorErrorKey] = helpAnchor as AnyObject
    }
  }

  if let recoverableError = error as? RecoverableError {
    result[NSLocalizedRecoveryOptionsErrorKey] =
      recoverableError.recoveryOptions as AnyObject
    result[NSRecoveryAttempterErrorKey] =
      _NSErrorRecoveryAttempter(error: recoverableError)
  }

  return result as AnyObject
}

// NSError and CFError conform to the standard ErrorProtocol protocol. Compiler
// magic allows this to be done as a "toll-free" conversion when an NSError
// or CFError is used as an ErrorProtocol existential.

extension NSError : ErrorProtocol {
  public var _domain: String { return domain }
  public var _code: Int { return code }
  public var _userInfo: AnyObject? { return userInfo as AnyObject }
}

extension CFError : ErrorProtocol {
  public var _domain: String {
    return CFErrorGetDomain(self) as String
  }

  public var _code: Int {
    return CFErrorGetCode(self)
  }

  public var _userInfo: AnyObject? {
    return CFErrorCopyUserInfo(self) as AnyObject?
  }
}

// An error value to use when an Objective-C API indicates error
// but produces a nil error object.
public enum _GenericObjCError : ErrorProtocol {
  case nilError
}

/// An internal protocol to represent Swift error enums that map to standard
/// Cocoa NSError domains.
public protocol _ObjectiveCBridgeableErrorProtocol : ErrorProtocol {
  /// Produce a value of the error type corresponding to the given NSError,
  /// or return nil if it cannot be bridged.
  init?(_bridgedNSError: NSError)
}

/// A hook for the runtime to use _ObjectiveCBridgeableErrorProtocol in order to
/// attempt an "errorTypeValue as? SomeError" cast.
///
/// If the bridge succeeds, the bridged value is written to the uninitialized
/// memory pointed to by 'out', and true is returned. Otherwise, 'out' is
/// left uninitialized, and false is returned.
@_silgen_name("swift_stdlib_bridgeNSErrorToErrorProtocol")
public func _stdlib_bridgeNSErrorToErrorProtocol<
  T : _ObjectiveCBridgeableErrorProtocol
>(_ error: NSError, out: UnsafeMutablePointer<T>) -> Bool {
  if let bridged = T(_bridgedNSError: error) {
    out.initialize(with: bridged)
    return true
  } else {
    return false
  }
}

/// Helper protocol for _BridgedNSError, which used to provide
/// default implementations.
public protocol __BridgedNSError : RawRepresentable, ErrorProtocol {
  static var _nsErrorDomain: String { get }
}

// Allow two bridged NSError types to be compared.
public func ==<T: __BridgedNSError>(lhs: T, rhs: T) -> Bool
  where T.RawValue: SignedInteger {
  return lhs.rawValue.toIntMax() == rhs.rawValue.toIntMax()
}

public extension __BridgedNSError where RawValue: SignedInteger {
  public final var _domain: String { return Self._nsErrorDomain }
  public final var _code: Int { return Int(rawValue.toIntMax()) }

  public init?(rawValue: RawValue) {
    self = unsafeBitCast(rawValue, to: Self.self)
  }

  public init?(_bridgedNSError: NSError) {
    if _bridgedNSError.domain != Self._nsErrorDomain {
      return nil
    }

    self.init(rawValue: RawValue(IntMax(_bridgedNSError.code)))
  }

  public final var hashValue: Int { return _code }
}

// Allow two bridged NSError types to be compared.
public func ==<T: __BridgedNSError>(lhs: T, rhs: T) -> Bool
  where T.RawValue: UnsignedInteger {
  return lhs.rawValue.toUIntMax() == rhs.rawValue.toUIntMax()
}


public extension __BridgedNSError where RawValue: UnsignedInteger {
  public final var _domain: String { return Self._nsErrorDomain }
  public final var _code: Int {
    return Int(bitPattern: UInt(rawValue.toUIntMax()))
  }

  public init?(rawValue: RawValue) {
    self = unsafeBitCast(rawValue, to: Self.self)
  }

  public init?(_bridgedNSError: NSError) {
    if _bridgedNSError.domain != Self._nsErrorDomain {
      return nil
    }

    self.init(rawValue: RawValue(UIntMax(UInt(_bridgedNSError.code))))
  }

  public final var hashValue: Int { return _code }
}

/// Describes a raw representable type that is bridged to a particular
/// NSError domain.
///
/// This protocol is used primarily to generate the conformance to
/// _ObjectiveCBridgeableErrorProtocol for such an enum.
public protocol _BridgedNSError : __BridgedNSError,
                                  _ObjectiveCBridgeableErrorProtocol,
                                  Hashable {
  /// The NSError domain to which this type is bridged.
  static var _nsErrorDomain: String { get }
}

/// Enumeration that describes the error codes within the Cocoa error
/// domain.
public struct NSCocoaError : RawRepresentable, _BridgedNSError {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static var _nsErrorDomain: String { return NSCocoaErrorDomain }
}

public func ~=(match: NSCocoaError, error: ErrorProtocol) -> Bool {
  guard let cocoaError = error as? NSCocoaError else { return false }
  return match.rawValue == cocoaError.rawValue
}

public extension NSCocoaError {
  public static var fileNoSuchFileError: NSCocoaError {
    return NSCocoaError(rawValue: 4)
  }
  public static var fileLockingError: NSCocoaError {
    return NSCocoaError(rawValue: 255)
  }
  public static var fileReadUnknownError: NSCocoaError {
    return NSCocoaError(rawValue: 256)
  }
  public static var fileReadNoPermissionError: NSCocoaError {
    return NSCocoaError(rawValue: 257)
  }
  public static var fileReadInvalidFileNameError: NSCocoaError {
    return NSCocoaError(rawValue: 258)
  }
  public static var fileReadCorruptFileError: NSCocoaError {
    return NSCocoaError(rawValue: 259)
  }
  public static var fileReadNoSuchFileError: NSCocoaError {
    return NSCocoaError(rawValue: 260)
  }
  public static var fileReadInapplicableStringEncodingError: NSCocoaError {
    return NSCocoaError(rawValue: 261)
  }
  public static var fileReadUnsupportedSchemeError: NSCocoaError {
    return NSCocoaError(rawValue: 262)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var fileReadTooLargeError: NSCocoaError {
    return NSCocoaError(rawValue: 263)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var fileReadUnknownStringEncodingError: NSCocoaError {
    return NSCocoaError(rawValue: 264)
  }

  public static var fileWriteUnknownError: NSCocoaError {
    return NSCocoaError(rawValue: 512)
  }
  public static var fileWriteNoPermissionError: NSCocoaError {
    return NSCocoaError(rawValue: 513)
  }
  public static var fileWriteInvalidFileNameError: NSCocoaError {
    return NSCocoaError(rawValue: 514)
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 5.0)
  public static var fileWriteFileExistsError: NSCocoaError {
    return NSCocoaError(rawValue: 516)
  }

  public static var fileWriteInapplicableStringEncodingError: NSCocoaError {
    return NSCocoaError(rawValue: 517)
  }
  public static var fileWriteUnsupportedSchemeError: NSCocoaError {
    return NSCocoaError(rawValue: 518)
  }
  public static var fileWriteOutOfSpaceError: NSCocoaError {
    return NSCocoaError(rawValue: 640)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var fileWriteVolumeReadOnlyError: NSCocoaError {
    return NSCocoaError(rawValue: 642)
  }

  @available(OSX, introduced: 10.11) @available(iOS, unavailable)
  public static var fileManagerUnmountUnknownError: NSCocoaError {
    return NSCocoaError(rawValue: 768)
  }

  @available(OSX, introduced: 10.11) @available(iOS, unavailable)
  public static var fileManagerUnmountBusyError: NSCocoaError {
    return NSCocoaError(rawValue: 769)
  }

  public static var keyValueValidationError: NSCocoaError {
    return NSCocoaError(rawValue: 1024)
  }
  public static var formattingError: NSCocoaError {
    return NSCocoaError(rawValue: 2048)
  }
  public static var userCancelledError: NSCocoaError {
    return NSCocoaError(rawValue: 3072)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var featureUnsupportedError: NSCocoaError {
    return NSCocoaError(rawValue: 3328)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableNotLoadableError: NSCocoaError {
    return NSCocoaError(rawValue: 3584)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableArchitectureMismatchError: NSCocoaError {
    return NSCocoaError(rawValue: 3585)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableRuntimeMismatchError: NSCocoaError {
    return NSCocoaError(rawValue: 3586)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableLoadError: NSCocoaError {
    return NSCocoaError(rawValue: 3587)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableLinkError: NSCocoaError {
    return NSCocoaError(rawValue: 3588)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadCorruptError: NSCocoaError {
    return NSCocoaError(rawValue: 3840)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadUnknownVersionError: NSCocoaError {
    return NSCocoaError(rawValue: 3841)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadStreamError: NSCocoaError {
    return NSCocoaError(rawValue: 3842)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListWriteStreamError: NSCocoaError {
    return NSCocoaError(rawValue: 3851)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var propertyListWriteInvalidError: NSCocoaError {
    return NSCocoaError(rawValue: 3852)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionInterrupted: NSCocoaError {
    return NSCocoaError(rawValue: 4097)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionInvalid: NSCocoaError {
    return NSCocoaError(rawValue: 4099)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionReplyInvalid: NSCocoaError {
    return NSCocoaError(rawValue: 4101)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileUnavailableError: NSCocoaError {
    return NSCocoaError(rawValue: 4353)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileNotUploadedDueToQuotaError: NSCocoaError {
    return NSCocoaError(rawValue: 4354)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileUbiquityServerNotAvailable: NSCocoaError {
    return NSCocoaError(rawValue: 4355)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityHandoffFailedError: NSCocoaError {
    return NSCocoaError(rawValue: 4608)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityConnectionUnavailableError: NSCocoaError {
    return NSCocoaError(rawValue: 4609)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityRemoteApplicationTimedOutError: NSCocoaError {
    return NSCocoaError(rawValue: 4610)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityHandoffUserInfoTooLargeError: NSCocoaError {
    return NSCocoaError(rawValue: 4611)
  }

  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public static var coderReadCorruptError: NSCocoaError {
    return NSCocoaError(rawValue: 4864)
  }

  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public static var coderValueNotFoundError: NSCocoaError {
    return NSCocoaError(rawValue: 4865)
  }


  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public var isCoderError: Bool {
    return rawValue >= 4864 && rawValue <= 4991
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public var isExecutableError: Bool {
    return rawValue >= 3584 && rawValue <= 3839
  }

  public var isFileError: Bool {
    return rawValue >= 0 && rawValue <= 1023
  }

  public var isFormattingError: Bool {
    return rawValue >= 2048 && rawValue <= 2559
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public var isPropertyListError: Bool {
    return rawValue >= 3840 && rawValue <= 4095
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public var isUbiquitousFileError: Bool {
    return rawValue >= 4352 && rawValue <= 4607
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public var isUserActivityError: Bool {
    return rawValue >= 4608 && rawValue <= 4863
  }

  public var isValidationError: Bool {
    return rawValue >= 1024 && rawValue <= 2047
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public var isXPCConnectionError: Bool {
    return rawValue >= 4096 && rawValue <= 4224
  }
}

extension NSCocoaError {
  @available(*, unavailable, renamed: "fileNoSuchFileError")
  public static var FileNoSuchFileError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileLockingError")
  public static var FileLockingError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadUnknownError")
  public static var FileReadUnknownError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadNoPermissionError")
  public static var FileReadNoPermissionError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadInvalidFileNameError")
  public static var FileReadInvalidFileNameError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadCorruptFileError")
  public static var FileReadCorruptFileError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadNoSuchFileError")
  public static var FileReadNoSuchFileError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadInapplicableStringEncodingError")
  public static var FileReadInapplicableStringEncodingError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadUnsupportedSchemeError")
  public static var FileReadUnsupportedSchemeError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadTooLargeError")
  public static var FileReadTooLargeError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadUnknownStringEncodingError")
  public static var FileReadUnknownStringEncodingError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteUnknownError")
  public static var FileWriteUnknownError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteNoPermissionError")
  public static var FileWriteNoPermissionError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteInvalidFileNameError")
  public static var FileWriteInvalidFileNameError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteFileExistsError")
  public static var FileWriteFileExistsError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteInapplicableStringEncodingError")
  public static var FileWriteInapplicableStringEncodingError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteUnsupportedSchemeError")
  public static var FileWriteUnsupportedSchemeError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteOutOfSpaceError")
  public static var FileWriteOutOfSpaceError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteVolumeReadOnlyError")
  public static var FileWriteVolumeReadOnlyError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileManagerUnmountUnknownError")
  public static var FileManagerUnmountUnknownError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileManagerUnmountBusyError")
  public static var FileManagerUnmountBusyError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "keyValueValidationError")
  public static var KeyValueValidationError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "formattingError")
  public static var FormattingError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userCancelledError")
  public static var UserCancelledError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "featureUnsupportedError")
  public static var FeatureUnsupportedError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableNotLoadableError")
  public static var ExecutableNotLoadableError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableArchitectureMismatchError")
  public static var ExecutableArchitectureMismatchError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableRuntimeMismatchError")
  public static var ExecutableRuntimeMismatchError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableLoadError")
  public static var ExecutableLoadError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableLinkError")
  public static var ExecutableLinkError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListReadCorruptError")
  public static var PropertyListReadCorruptError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListReadUnknownVersionError")
  public static var PropertyListReadUnknownVersionError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListReadStreamError")
  public static var PropertyListReadStreamError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListWriteStreamError")
  public static var PropertyListWriteStreamError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListWriteInvalidError")
  public static var PropertyListWriteInvalidError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "xpcConnectionInterrupted")
  public static var XPCConnectionInterrupted: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "xpcConnectionInvalid")
  public static var XPCConnectionInvalid: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "xpcConnectionReplyInvalid")
  public static var XPCConnectionReplyInvalid: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "ubiquitousFileUnavailableError")
  public static var UbiquitousFileUnavailableError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "ubiquitousFileNotUploadedDueToQuotaError")
  public static var UbiquitousFileNotUploadedDueToQuotaError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "ubiquitousFileUbiquityServerNotAvailable")
  public static var UbiquitousFileUbiquityServerNotAvailable: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityHandoffFailedError")
  public static var UserActivityHandoffFailedError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityConnectionUnavailableError")
  public static var UserActivityConnectionUnavailableError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityRemoteApplicationTimedOutError")
  public static var UserActivityRemoteApplicationTimedOutError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityHandoffUserInfoTooLargeError")
  public static var UserActivityHandoffUserInfoTooLargeError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "coderReadCorruptError")
  public static var CoderReadCorruptError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "coderValueNotFoundError")
  public static var CoderValueNotFoundError: NSCocoaError {
    fatalError("unavailable accessor can't be called")
  }
}

/// Enumeration that describes the error codes within the NSURL error
/// domain.
@objc public enum NSURLError : Int, _BridgedNSError {
  case unknown = -1
  case cancelled = -999
  case badURL = -1000
  case timedOut = -1001
  case unsupportedURL = -1002
  case cannotFindHost = -1003
  case cannotConnectToHost = -1004
  case networkConnectionLost = -1005
  case dnsLookupFailed = -1006
  case httpTooManyRedirects = -1007
  case resourceUnavailable = -1008
  case notConnectedToInternet = -1009
  case redirectToNonExistentLocation = -1010
  case badServerResponse = -1011
  case userCancelledAuthentication = -1012
  case userAuthenticationRequired = -1013
  case zeroByteResource = -1014
  case cannotDecodeRawData = -1015
  case cannotDecodeContentData = -1016
  case cannotParseResponse = -1017
  case fileDoesNotExist = -1100
  case fileIsDirectory = -1101
  case noPermissionsToReadFile = -1102
  case secureConnectionFailed = -1200
  case serverCertificateHasBadDate = -1201
  case serverCertificateUntrusted = -1202
  case serverCertificateHasUnknownRoot = -1203
  case serverCertificateNotYetValid = -1204
  case clientCertificateRejected = -1205
  case clientCertificateRequired = -1206
  case cannotLoadFromNetwork = -2000
  case cannotCreateFile = -3000
  case cannotOpenFile = -3001
  case cannotCloseFile = -3002
  case cannotWriteToFile = -3003
  case cannotRemoveFile = -3004
  case cannotMoveFile = -3005
  case downloadDecodingFailedMidStream = -3006
  case downloadDecodingFailedToComplete = -3007

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  case internationalRoamingOff = -1018

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  case callIsActive = -1019

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  case dataNotAllowed = -1020

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  case requestBodyStreamExhausted = -1021

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  case backgroundSessionRequiresSharedContainer = -995

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  case backgroundSessionInUseByAnotherProcess = -996

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  case backgroundSessionWasDisconnected = -997

  public static var _nsErrorDomain: String { return NSURLErrorDomain }
}

extension NSURLError {
  @available(*, unavailable, renamed: "unknown")
  static var Unknown: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cancelled")
  static var Cancelled: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "badURL")
  static var BadURL: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "timedOut")
  static var TimedOut: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "unsupportedURL")
  static var UnsupportedURL: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotFindHost")
  static var CannotFindHost: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotConnectToHost")
  static var CannotConnectToHost: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "networkConnectionLost")
  static var NetworkConnectionLost: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "dnsLookupFailed")
  static var DNSLookupFailed: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "httpTooManyRedirects")
  static var HTTPTooManyRedirects: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "resourceUnavailable")
  static var ResourceUnavailable: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "notConnectedToInternet")
  static var NotConnectedToInternet: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "redirectToNonExistentLocation")
  static var RedirectToNonExistentLocation: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "badServerResponse")
  static var BadServerResponse: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userCancelledAuthentication")
  static var UserCancelledAuthentication: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userAuthenticationRequired")
  static var UserAuthenticationRequired: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "zeroByteResource")
  static var ZeroByteResource: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotDecodeRawData")
  static var CannotDecodeRawData: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotDecodeContentData")
  static var CannotDecodeContentData: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotParseResponse")
  static var CannotParseResponse: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileDoesNotExist")
  static var FileDoesNotExist: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileIsDirectory")
  static var FileIsDirectory: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "noPermissionsToReadFile")
  static var NoPermissionsToReadFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "secureConnectionFailed")
  static var SecureConnectionFailed: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateHasBadDate")
  static var ServerCertificateHasBadDate: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateUntrusted")
  static var ServerCertificateUntrusted: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateHasUnknownRoot")
  static var ServerCertificateHasUnknownRoot: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateNotYetValid")
  static var ServerCertificateNotYetValid: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "clientCertificateRejected")
  static var ClientCertificateRejected: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "clientCertificateRequired")
  static var ClientCertificateRequired: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotLoadFromNetwork")
  static var CannotLoadFromNetwork: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotCreateFile")
  static var CannotCreateFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotOpenFile")
  static var CannotOpenFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotCloseFile")
  static var CannotCloseFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotWriteToFile")
  static var CannotWriteToFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotRemoveFile")
  static var CannotRemoveFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotMoveFile")
  static var CannotMoveFile: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "downloadDecodingFailedMidStream")
  static var DownloadDecodingFailedMidStream: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "downloadDecodingFailedToComplete")
  static var DownloadDecodingFailedToComplete: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "internationalRoamingOff")
  static var InternationalRoamingOff: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "callIsActive")
  static var CallIsActive: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "dataNotAllowed")
  static var DataNotAllowed: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "requestBodyStreamExhausted")
  static var RequestBodyStreamExhausted: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "backgroundSessionRequiresSharedContainer")
  static var BackgroundSessionRequiresSharedContainer: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "backgroundSessionInUseByAnotherProcess")
  static var BackgroundSessionInUseByAnotherProcess: NSURLError {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "backgroundSessionWasDisconnected")
  static var BackgroundSessionWasDisconnected: NSURLError {
    fatalError("unavailable accessor can't be called")
  }
}

extension POSIXError : _BridgedNSError {
  public static var _nsErrorDomain: String { return NSPOSIXErrorDomain }
}

extension MachError : _BridgedNSError {
  public static var _nsErrorDomain: String { return NSMachErrorDomain }
}

public struct ErrorUserInfoKey : RawRepresentable, _SwiftNewtypeWrapper, Equatable, Hashable, _ObjectiveCBridgeable {
  public init(rawValue: String) { self.rawValue = rawValue }
  public var rawValue: String
}

public extension ErrorUserInfoKey {
  @available(*, deprecated, renamed: "NSUnderlyingErrorKey")
  static let underlyingErrorKey = ErrorUserInfoKey(rawValue: NSUnderlyingErrorKey)

  @available(*, deprecated, renamed: "NSLocalizedDescriptionKey")
  static let localizedDescriptionKey = ErrorUserInfoKey(rawValue: NSLocalizedDescriptionKey)

  @available(*, deprecated, renamed: "NSLocalizedFailureReasonErrorKey")
  static let localizedFailureReasonErrorKey = ErrorUserInfoKey(rawValue: NSLocalizedFailureReasonErrorKey)

  @available(*, deprecated, renamed: "NSLocalizedRecoverySuggestionErrorKey")
  static let localizedRecoverySuggestionErrorKey = ErrorUserInfoKey(rawValue: NSLocalizedRecoverySuggestionErrorKey)

  @available(*, deprecated, renamed: "NSLocalizedRecoveryOptionsErrorKey")
  static let localizedRecoveryOptionsErrorKey = ErrorUserInfoKey(rawValue: NSLocalizedRecoveryOptionsErrorKey)

  @available(*, deprecated, renamed: "NSRecoveryAttempterErrorKey")
  static let recoveryAttempterErrorKey = ErrorUserInfoKey(rawValue: NSRecoveryAttempterErrorKey)

  @available(*, deprecated, renamed: "NSHelpAnchorErrorKey")
  static let helpAnchorErrorKey = ErrorUserInfoKey(rawValue: NSHelpAnchorErrorKey)

  @available(*, deprecated, renamed: "NSStringEncodingErrorKey")
  static let stringEncodingErrorKey = ErrorUserInfoKey(rawValue: NSStringEncodingErrorKey)

  @available(*, deprecated, renamed: "NSURLErrorKey")
  static let NSURLErrorKey = ErrorUserInfoKey(rawValue: Foundation.NSURLErrorKey)

  @available(*, deprecated, renamed: "NSFilePathErrorKey")
  static let filePathErrorKey = ErrorUserInfoKey(rawValue: NSFilePathErrorKey)
}
