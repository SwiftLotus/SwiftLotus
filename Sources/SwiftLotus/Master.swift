//
//  Master.swift
//  SwiftLotusPackageDescription
//
//  Created by billchan on 06/04/2018.
//

import Foundation
import Socket

#if os(Linux)
import Glibc
#endif


fileprivate let killWorkerTimerTime: Int = 2
fileprivate let defaultBackLogLength: Int = 102400
fileprivate let maxUDPPackageSize: Int = 65535

enum Transport {
    case tcp
    case udp
    case unix
    case ssl
}

enum EventLoop {
    case libevent
    case event
}

enum OS {
    case linux
    case macOS
    case windows
}

enum Status {
    case starting
    case running
    case shutdown
    case reloading
}

public class Master {
    
    /// Worker id.
    var id: Int = 0
    
    /// Name of the worker processes.
    var name: String = "none"
    
    /// Number of worker processes.
    var count: Int = 1
    
    /// Unix user of processes, needs appropriate privileges (usually root).
    var user: String = ""
    
    /// Unix group of processes, needs appropriate privileges (usually root).
    var group: String = ""
    
    /// reloadable.
    var isReloadable: Bool = true
    
    /// reuse port.
    var isReusePort: Bool = false
    
    /// Emitted when worker processes start.
    var onWorkerStart: (()->())?
    
    /// Emitted when a socket connection is successfully established.
    var onConnect: (()->())?
    
    /// Emitted when data is received.
    var onMessage: (()->())?
    
    /// Emitted when the other end of the socket sends a FIN packet.
    var onClose: (()->())?
    
    /// Emitted when an error occurs with connection.
    var onError: (()->())?
    
    /// Emitted when the send buffer becomes full.
    var onBufferFull: (()->())?
    
    /// Emitted when the send buffer becomes empty.
    var onBufferDrain: (()->())?
    
    /// Emitted when worker processes stoped.
    var onWorkerStop: (()->())?
    
    /// Emitted when worker processes get reload signal.
    var onWorkerReload: (()->())?
    
    /// Transport layer protocol.
    var transport: Transport = .tcp
    
    /// Store all connections of clients.
    var connections: [AnyObject] = []
    
    /// Application layer protocol.
    var `protocol`: String = ""
    
    /// Root path for autoload.
    fileprivate var autoloadRootPath: String = ""
    
    /// Pause accept new connections or not.
    fileprivate var isPauseAccept: Bool = true
    
    /// Is worker stopping ?
    var isStopping = false
    
    /// Daemonize.
    static var isDaemonize: Bool = false
    
    /// Stdout file.
    static var stdoutFile: String = "/dev/null"
    
    /// The file to store master process PID.
    static var pidFile: String = ""
    
    /// Log file.
    static var logFile: String = ""
    
    /// Global event loop.
    static var globalEvent: EventLoop?
    
    /// Emitted when the master process get reload signal.
    static var onMasterReload: (()->())?
    
    /// Emitted when the master process terminated.
    static var onMasterStop: (()->())?
    
    /// EventLoopClass
    static var eventLoopClass: AnyClass?
    
    /// The PID of master process.
    fileprivate static var masterPid: Int = 0
    
    /// Listening socket.
    fileprivate static var mainSocket: AnyObject?
    
    /// Socket name. The format is like this http://0.0.0.0:80 .
    fileprivate var socketName: String = ""
    
    /// Context of socket.
    fileprivate var context: AnyObject?
    
    /// All worker instances.
    fileprivate static var workers: [AnyObject] = []
    
    /// All worker porcesses pid.
    /// The format is like this [worker_id = [pid = pid, pid = pid, ..], ..]
    fileprivate static var pidMap: [AnyObject] = []
    
    /// All worker processes waiting for restart.
    /// The format is like this [pid = pid, pid = pid].
    fileprivate static var pidsToRestart: [AnyObject] = []
    
    /// Mapping from PID to worker process ID.
    /// The format is like this [worker_id = [0 = pid, 1 = pid, ..], ..].
    fileprivate static var idMap: [AnyObject] = []
    
    /// Current status.
    fileprivate static var status: Status = .starting
    
    /// Maximum length of the worker names.
    fileprivate static var maxWorkerNameLength: Int = 12
    
    /// Maximum length of the socket names.
    fileprivate static var maxSocketNameLength: Int = 12
    
    /// Maximum length of the process user names.
    fileprivate static var maxUserNameLength: Int = 12
    
    /// The file to store status info of current worker process.
    fileprivate static var statisticsFile: String = ""
    
    /// Start file.
    fileprivate static var startFile: String = ""
    
    /// OS.
    fileprivate static var os: OS = .linux
    
    /// Processes for windows.
    fileprivate static var processForWindows: [AnyObject] = []
    
    /// Start Timestamp.
    fileprivate static var startTimestamp: Int = 0
    
    /// Information of worker when exit.
    fileprivate static var workerExitInfo: [AnyObject] = []
    
    /// Available event loops.
    fileprivate static var availableEventLoops: [String: EventLoop] = [String: EventLoop]()
    
    /// Built-in protocols.
    fileprivate static var builtinTransports: [String: Transport] = [String: Transport]()
    
    /// Graceful stop or not.
    fileprivate static var isGracefulStop: Bool = false


    fileprivate static var listenSocket: Socket? = nil
    fileprivate static var family: Socket.ProtocolFamily = .inet
    fileprivate static var port: Int32 = 9527

    /// Run all worker instances
    static func run() {
        self.checkEnv()
        self.commonInit()
        self.parseCommand()
        self.daemonize()
        self.initSocket()
        self.installSignal()
//        self.saveMasterPid()，保存主进程id，放到commonInit里面去
        self.displayUI()
        self.forkWorkers()
        self.resetStd()
        self.monitorWorkers()
    }
    
    /// Check Env.
    /// 查看环境变量
    fileprivate static func checkEnv() {
        
    }
    
    /// Common Init.
    /// 初始化pid，日志，统计，和设置主进程名称
    fileprivate static func commonInit() {
        
    }
    
    /// Init Socket
    /// 建立socket连接，阻塞在listen中
    fileprivate static func initSocket() {
        do {
            try self.listenSocket = Socket.create(family: family)

            guard let listener = self.listenSocket else {
                print("Unable to unwrap socket...")
                return
            }
            try listener.listen(on: Int(self.port), maxBacklogSize: 10)
        } catch let error {

            guard let socketError = error as? Socket.Error else {
                print("Unexpected error...")
                return
            }

            print("serverHelper Error reported: \(socketError.description)")
        }

    }
    
    /// Get all worker instances.
    ///
    /// - Returns: workers array
    fileprivate static func getAllWorkers() -> [AnyObject] {
        return []
    }
    
    /// Get global event-loop instance.
    ///
    /// - Returns: EventInterface
    static func getEventLoop() -> String {
        // TODO: get Event
        return "EventInterface"
    }
    
    /// Init idMap.
    fileprivate static func initId() {
        
    }
    
    /// Get unix user of current porcess.
    fileprivate static func getCurrentUser() -> String {
        return ""
    }
    
    /// Display staring UI.
    fileprivate static func displayUI() {
        
    }
    
    /// Parse command.
    /// 解析命令行参数:  start,  stop,  restart,  reload,  status,  connections
    fileprivate static func parseCommand() {
        
    }
    
    /// Format status data.
    fileprivate static func formatStatusData() {
        
    }
    
    /// Install signal handler.
    /// 信号处理
    fileprivate static func installSignal() {
        
    }
    
    /// Reinstall signal handler.
    fileprivate static func reinstallSignal() {
        
    }
    
    /// Signal handler.
    ///
    /// - Returns: signal
    static func signalHandler() -> Int {
        return 0
    }
    
    /// Run as deamon mode.
    fileprivate static func daemonize() {
        
    }
    
    /// Save pid.
    fileprivate static func saveMasterPid() {
        
    }
    
    /// Get event loop name.
    fileprivate static func getEventLoopName() -> String {
        return ""
    }
    
    /// Get all pids of worker processes.
    ///
    /// - Returns: worker processes Array
    fileprivate static func getAllWorkerPids() -> [AnyObject] {
        return []
    }
    
    /// Fork some worker processes.
    fileprivate static func forkWorkers() {
        switch Master.os {
            case .linux:
                // TODO: forkWorkersForLinux
                break
            case .macOS:
                // TODO: forkWorkersForMacOS
                break
            case .windows:
                // TODO: forkWorkersForWindows
                break
        }
    }
    
    /// Redirect standard input and output.
    fileprivate static func resetStd() {
        if !Master.isDaemonize || Master.os != .linux {
            return
        }
        // TODO: reset file std
    }
    
    fileprivate static func monitorWorkers() {
        switch Master.os {
            case .linux:
                // TODO: monitorWorkersForLinux
                break
            case .macOS:
                // TODO: monitorWorkersForMacOS
                break
            case .windows:
                // TODO: monitorWorkersForWindows
                break
        }
    }
    
}
