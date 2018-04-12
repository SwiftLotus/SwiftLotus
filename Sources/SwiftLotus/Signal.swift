//
// Created by 杨晖 on 2018/4/12.
//

import Foundation
#if os(Linux)
import Glibc
#endif

enum Signal:Int32 {
    case INT    = 2
    case TERM   = 15
    case USR1   = 10
    case QUIT   = 3
    case USR2   = 12
    case IO     = 19
    case PIPE   = 13
}

typealias SigactionHandler = @convention(c)(Int32) -> Void

func trap(signalNumber:Signal, action:SigactionHandler) {
    var sigAction = sigaction()

    sigAction.__sigaction_handler = unsafeBitCast(action, to: sigaction.__Unnamed_union___sigaction_handler.self)

    sigaction(signalNumber.rawValue, &sigAction, nil)
}


//typealias SignalHandler = __sighandler_t
//
//func trap(signum:Signal, action:SignalHandler) {
//    signal(signum.rawValue, action)
//}
