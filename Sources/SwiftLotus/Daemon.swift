//
//  Daemon.swift
//  SwiftLotusPackageDescription
//
//  Created by 杨晖 on 2018/4/7.
//

import Foundation

import Foundation

#if os(Linux)
import Glibc
#endif


class Daemon {
    init() {
        #if os(Linux)

        var pid = fork()
        
        if -1 == pid {
            exit(0)
            // 异常处理
        } else if pid > 0 { // 父进程
            exit(0)
        }
        
        if -1 == setsid() {
            exit(0)
        }
        // Fork again avoid SVR4 system regain the control of terminal.
        pid = fork();
        if -1 == pid {
            exit(0)
        } else if pid > 0 {
            exit(0);
        }
        #endif
    }
    
    func create(work: ()->()) {
        #if os(Linux)

        let pid = fork()
        
        if -1 == pid {
            // 异常处理
        } else if pid > 0 { // 父进程
            exit(0)
        }
        work()
        #endif

    }
    
    
}
