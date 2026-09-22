import Flutter
import UIKit
import dnssd

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var dnsQueries: [ObjectIdentifier: SystemDnsQuery] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    let error = DNSServiceQueryRecord(
      &serviceRef,
      DNSServiceFlags(kDNSServiceFlagsTimeout),
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
