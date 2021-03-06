//
//  Logger.swift
//  JustLog
//
//  Created by Alberto De Bortoli on 06/12/2016.
//  Copyright © 2017 Just Eat. All rights reserved.
//

import Foundation
import SwiftyBeaver

@objc
public final class Logger: NSObject {
    
    public var logTypeKey = "log_type"
    
    public var fileKey = "file"
    public var functionKey = "function"
    public var lineKey = "line"
    public var queueLabelKey = "queue_label"
    
    public var appVersionKey = "app_version"
    public var iosVersionKey = "ios_version"
    public var deviceTypeKey = "ios_device"
    
    public var errorDomain = "error_domain"
    public var errorCode = "error_code"
    
    public static let shared = Logger()
    
    // file conf
    public var logFilename: String?
    
    // logstash conf
    public var logstashHost: String!
    public var logstashPort: UInt16 = 9300
    public var logstashTimeout: TimeInterval = 20
    public var logLogstashSocketActivity: Bool = false
    public var logzioToken: String?
    
    // logger conf
    public var defaultUserInfo: [String : Any]?
    public var enableConsoleLogging: Bool = true
    public var enableFileLogging: Bool = true
    public var enableLogstashLogging: Bool = true
    public let internalLogger = SwiftyBeaver.self
    private var dispatchTimer: Timer?
    
    // destinations
    public var console: ConsoleDestination!
    public var logstash: LogstashDestination!
    public var file: FileDestination!
    
    deinit {
        dispatchTimer?.invalidate()
        dispatchTimer = nil
    }
    
    public func setup() {
        let format = "$C $Dyyyy-MM-dd HH:mm:ss.SSS$d $X: $M"
        
        // console
        if enableConsoleLogging {
            console = JustLog.ConsoleDestination()
            console.format = format
            internalLogger.addDestination(console)
        }
        
        // file
        if enableFileLogging {
            file = JustLog.FileDestination()
            file.format = format
            if let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                file.logFileURL = baseURL.appendingPathComponent(logFilename ?? "justlog.log", isDirectory: false)
            }
            internalLogger.addDestination(file)
        }
        
        // logstash
        if enableLogstashLogging {
            logstash = LogstashDestination(host: logstashHost, port: logstashPort, timeout: logstashTimeout, logActivity: logLogstashSocketActivity)
            logstash.logzioToken = logzioToken
            internalLogger.addDestination(logstash)
        }
        
        dispatchTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(scheduledForceSend(_:)), userInfo: nil, repeats: true)
    }
    
    public func forceSend(_ completionHandler: @escaping (_ error: Error?) -> Void = {_ in }) {
        if enableLogstashLogging {
            logstash.forceSend(completionHandler)
        }
    }
    
    public func cancelSending() {
        if enableLogstashLogging {
            logstash.cancelSending()
        }
    }
}

extension Logger: Logging {
    
    public func verbose(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        let updatedUserInfo = [logTypeKey: "verbose"].merged(with: userInfo ?? [String : String]())
        let logMessage = self.logMessage(message, error: error, userInfo: updatedUserInfo, file, function, line, currentQueueLabel())
        internalLogger.verbose(logMessage, file, function, line: Int(line), context: currentQueueLabel())
    }
    
    public func debug(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        let updatedUserInfo = [logTypeKey: "debug"].merged(with: userInfo ?? [String : String]())
        let logMessage = self.logMessage(message, error: error, userInfo: updatedUserInfo, file, function, line, currentQueueLabel())
        internalLogger.debug(logMessage, file, function, line: Int(line), context: currentQueueLabel())
    }
    
    public func info(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        let updatedUserInfo = [logTypeKey: "info"].merged(with: userInfo ?? [String : String]())
        let logMessage = self.logMessage(message, error: error, userInfo: updatedUserInfo, file, function, line, currentQueueLabel())
        internalLogger.info(logMessage, file, function, line: Int(line), context: currentQueueLabel())
    }
    
    public func warning(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        let updatedUserInfo = [logTypeKey: "warning"].merged(with: userInfo ?? [String : String]())
        let logMessage = self.logMessage(message, error: error, userInfo: updatedUserInfo, file, function, line, currentQueueLabel())
        internalLogger.warning(logMessage, file, function, line: Int(line), context: currentQueueLabel())
    }
    
    public func error(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        let updatedUserInfo = [logTypeKey: "error"].merged(with: userInfo ?? [String : Any]())
        let logMessage = self.logMessage(message, error: error, userInfo: updatedUserInfo, file, function, line, currentQueueLabel())
        internalLogger.error(logMessage, file, function, line: Int(line), context: currentQueueLabel())
    }
    
}

extension Logger {

    fileprivate func currentQueueLabel() -> String {
        if let name = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8) {
            return name
        } else {
            return ""
        }
    }
    
    fileprivate func logMessage(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: String, _ function: String, _ line: UInt, _ context: Any? = nil) -> String {
        
        let messageConst = "message"
        let userInfoConst = "userInfo"
        let metadataConst = "metadata"
        
        var options = defaultUserInfo ?? [String : Any]()
        
        var retVal = [String : Any]()
        retVal[messageConst] = message
        
        var fileMetadata = [String : String]()
        
        if let url = URL(string: file) {
            fileMetadata[fileKey] = URLComponents(url: url, resolvingAgainstBaseURL: false)?.url?.pathComponents.last ?? file
        }
        
        fileMetadata[functionKey] = function
        fileMetadata[lineKey] = String(line)
        fileMetadata[queueLabelKey] = String(describing: context)
        
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"], let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] {
            fileMetadata[appVersionKey] = "\(bundleShortVersion) (\(bundleVersion))"
        }
        
        fileMetadata[iosVersionKey] = UIDevice.current.systemVersion
        fileMetadata[deviceTypeKey] = UIDevice.current.platform()
        
        retVal[metadataConst] = fileMetadata
        
        if let userInfo = userInfo {
            for (key, value) in userInfo {
                _ = options.updateValue(value, forKey: key)
            }
        }
        
        if let error = error {
            let errorInfo = [errorDomain: error.domain,
                             errorCode: error.code] as [String : Any]
            let errorUserInfo = error.humanReadableError().userInfo
            options = options.merged(with: errorInfo).merged(with: errorUserInfo.flattened())
        }
        
        retVal[userInfoConst] = options
        
        return retVal.toJSON() ?? ""
    }
    
    @objc fileprivate func scheduledForceSend(_ timer: Timer) {
        forceSend()
    }
    
}
