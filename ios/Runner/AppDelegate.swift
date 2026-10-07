import Flutter
import UIKit
import dnssd
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var dnsQueries: [ObjectIdentifier: SystemDnsQuery] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeLocalDataFromBackup()
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Prevents Akshi's local database, preferences, and diagnostics from being
  /// included in ordinary iCloud and device backups.
  private func excludeLocalDataFromBackup() {
    let fileManager = FileManager.default
    let directories: [FileManager.SearchPathDirectory] = [
      .documentDirectory,
      .libraryDirectory,
    ]

    for directory in directories {
      guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
        continue
      }
      do {
        try (url as NSURL).setResourceValue(
          true,
          forKey: URLResourceKey.isExcludedFromBackupKey
        )
      } catch {
        NSLog("Akshi could not exclude local data from backup: %@", String(describing: error))
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.aliyesha.akshi/dns",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "query" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let name = arguments["name"] as? String,
        let type = arguments["type"] as? NSNumber
      else {
        result(FlutterError(code: "invalid_arguments", message: "DNS name and type are required", details: nil))
        return
      }
      self?.startDnsQuery(name: name, type: UInt16(type.intValue), result: result)
    }

    let externalLinksChannel = FlutterMethodChannel(
      name: "com.aliyesha.akshi/external_links",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    externalLinksChannel.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let value = arguments["url"] as? String,
        let url = URL(string: value),
        url.scheme == "https",
        url.host?.isEmpty == false
      else {
        result(
          FlutterError(
            code: "invalid_url",
            message: "A valid HTTPS URL is required",
            details: nil
          )
        )
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }

    let systemSettingsChannel = FlutterMethodChannel(
      name: "com.aliyesha.akshi/system_settings",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    systemSettingsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "notificationPermissionStatus":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let status: String
          switch settings.authorizationStatus {
          case .authorized, .provisional:
            status = "allowed"
          case .denied:
            status = "notAllowed"
          case .notDetermined:
            status = "notDetermined"
          default:
            if #available(iOS 14.0, *),
               settings.authorizationStatus == .ephemeral {
              status = "allowed"
            } else {
              status = "unavailable"
            }
          }
          DispatchQueue.main.async { result(status) }
        }
      case "openNotificationSettings":
        let settingsUrlString: String
        if #available(iOS 16.0, *) {
          settingsUrlString = UIApplication.openNotificationSettingsURLString
        } else {
          settingsUrlString = UIApplication.openSettingsURLString
        }
        guard let settingsUrl = URL(string: settingsUrlString) else {
          result(false)
          return
        }
        UIApplication.shared.open(settingsUrl, options: [:]) { opened in
          result(opened)
        }
      case "markNotificationPermissionRequested":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startDnsQuery(name: String, type: UInt16, result: @escaping FlutterResult) {
    var query: SystemDnsQuery?
    query = SystemDnsQuery(name: name, type: type) { [weak self] query, records, error in
      DispatchQueue.main.async {
        self?.dnsQueries.removeValue(forKey: ObjectIdentifier(query))
        if let error {
          result(FlutterError(code: "dns_error", message: error, details: nil))
        } else {
          result(["records": records])
        }
      }
    }
    guard let query else { return }
    dnsQueries[ObjectIdentifier(query)] = query
    query.start()
  }
}

private final class SystemDnsQuery {
  typealias Completion = (SystemDnsQuery, [[String: Any]], String?) -> Void

  private let name: String
  private let type: UInt16
  private let completion: Completion
  private let queue = DispatchQueue(label: "com.aliyesha.akshi.dns")
  private var serviceRef: DNSServiceRef?
  private var records: [[String: Any]] = []
  private var completed = false

  init(name: String, type: UInt16, completion: @escaping Completion) {
    self.name = name
    self.type = type
    self.completion = completion
  }

  func start() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    // Request authoritative negative answers as callbacks. Without
    // ReturnIntermediates, DNSServiceQueryRecord keeps an NXDOMAIN query open;
    // the Timeout flag then reports a missing name as a resolver timeout.
    // Returning the negative answer lets every record type use the same
    // generic contract: records, an empty result, or an actual lookup error.
    let queryFlags = DNSServiceFlags(
      kDNSServiceFlagsTimeout | kDNSServiceFlagsReturnIntermediates
    )
    let error = DNSServiceQueryRecord(
      &serviceRef,
      queryFlags,
      0,
      name,
      type,
      UInt16(kDNSServiceClass_IN),
      systemDnsCallback,
      context
    )
    guard error == kDNSServiceErr_NoError, let serviceRef else {
      finish(error: "The system DNS resolver could not start (\(error)).")
      return
    }
    let dispatchError = DNSServiceSetDispatchQueue(serviceRef, queue)
    if dispatchError != kDNSServiceErr_NoError {
      finish(error: "The system DNS resolver could not be scheduled (\(dispatchError)).")
    }
  }

  func receive(
    flags: DNSServiceFlags,
    errorCode: DNSServiceErrorType,
    length: UInt16,
    owner: String,
    recordType: UInt16,
    ttl: UInt32,
    data: UnsafeRawPointer?
  ) {
    if errorCode == kDNSServiceErr_NoSuchRecord {
      finish(error: nil)
      return
    }
    guard errorCode == kDNSServiceErr_NoError else {
      finish(error: "DNS lookup failed (\(errorCode)).")
      return
    }
    // ReturnIntermediates may report an alias before the requested answer.
    // Keep waiting for the requested type so the native bridge has the same
    // one-query/one-type contract as Android.
    guard recordType == type else { return }

    if let data, length > 0 {
      records.append([
        "owner": owner.isEmpty ? name : owner,
        "type": Int(recordType),
        "ttl": Int(ttl),
        "data": FlutterStandardTypedData(
          bytes: Data(bytes: data, count: Int(length))
        ),
      ])
    }
    if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
      finish(error: nil)
    }
  }

  private func finish(error: String?) {
    guard !completed else { return }
    completed = true
    if let serviceRef {
      DNSServiceRefDeallocate(serviceRef)
      self.serviceRef = nil
    }
    completion(self, records, error)
  }

  deinit {
    if let serviceRef { DNSServiceRefDeallocate(serviceRef) }
  }
}

private let systemDnsCallback: DNSServiceQueryRecordReply = {
  _, flags, _, errorCode, fullname, recordType, _, dataLength, recordData, ttl, context in
  guard let context else { return }
  let query = Unmanaged<SystemDnsQuery>.fromOpaque(context).takeUnretainedValue()
  query.receive(
    flags: flags,
    errorCode: errorCode,
    length: dataLength,
    owner: fullname.map { String(cString: $0) } ?? "",
    recordType: recordType,
    ttl: ttl,
    data: recordData
  )
}
