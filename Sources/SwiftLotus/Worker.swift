//
//  Worker.swift
//  SwiftLotusPackageDescription
//
//  Created by billchan on 15/04/2018.
//

enum WorkerStatus {
    case starting
    case running
    case shutdown
    case reloading
}

enum WorkerEventLoop {
    case libevent
    case event
    
    func loop() {
        // TODO:
    }
}

import Foundation

public class Worker {
    
    /// Current status.
    fileprivate static var status: WorkerStatus = .starting
    
    /// Global event loop.
    fileprivate static var globalEvent: WorkerEventLoop?
    
    /// Listening socket.
    fileprivate var mainSocket: AnyObject?
    
    /// Graceful stop or not.
    fileprivate static var gracefulStop: Bool = false
    
    /// Store all connections of clients.
    var connections: [AnyObject] = []
    
    /// Emitted when data is received.
    var onMessage: (()->())?
    
    /// Emitted when worker processes start.
    var onWorkerStart: (()->())?
    
    /// Emitted when worker processes stoped.
    var onWorkerStop: (()->())?
    
    /// Emitted when the other end of the socket sends a FIN packet.
    var onClose: (()->())?
    
    /// Emitted when an error occurs with connection.
    var onError: (()->())?
    
    /// Emitted when the send buffer becomes full.
    var onBufferFull: (()->())?
    
    /// Emitted when the send buffer becomes empty.
    var onBufferDrain: (()->())?
    
    /// Run worker instance.
    func run() {
        
        // Update process state.
        Worker.status = .running;
        
        // Create a global event loop.
        if Worker.globalEvent == nil {
            Worker.globalEvent = Worker.getEventLoop()
            self.resumeAccept()
        }
        
        // Reinstall signal.
        Worker.reinstallSignal()
        
        // Init Timer. TODO: initWithEventLoop
        Timer.init()
        
        // Set an empty onMessage callback.
        if let onMessage = self.onMessage {
            onMessage()
        }
        
        // Try to emit onWorkerStart callback.
        if let onWorkerStart = self.onWorkerStart {
            onWorkerStart()
        }
        
        // Main loop.
        Worker.globalEvent!.loop()
        
    }
    
    /**
     * Stop current worker instance.
     *
     * @return void
     */
    func stop() {
        
        // Try to emit onWorkerStop callback.
        if let onWorkerStop = self.onWorkerStop {
            onWorkerStop()
        }
        
        // Remove listener for server socket.
        self.unlisten()

        // Close all connections for the worker.
        if !Worker.gracefulStop {
            for connection in self.connections {
                // connection.close()
            }
        }
        
        // Clear callback.
        self.onMessage = nil
        self.onClose = nil
        self.onError = nil
        self.onBufferDrain = nil
        self.onBufferFull = nil

    }
    
    /// Listen.
    func listen() {
        // TODO:
    }
    
    /// Unlisten.
    func unlisten() {
        self.pauseAccept()
        if let mainSocket = self.mainSocket {
            // fclose mainSocket
        }
    }
    
    /// Get event loop .
    ///
    /// - Returns: WorkerEventLoop
    static func getEventLoop() -> WorkerEventLoop {
        return .libevent
    }
    
    /// Resume accept new connections.
    func resumeAccept() {
        // Register a listener to be notified when server socket is ready to read.
    }
    
    /// Pause accept new connections.
    func pauseAccept() {
        
    }
    
    /// Reinstall signal handler.
    static func reinstallSignal() {
        
    }
    
}