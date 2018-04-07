//
//  UserCommand.swift
//  SwiftLotusPackageDescription
//
//  Created by 杨晖 on 2018/4/7.
//

import Foundation
enum Command: String {
    case start          = "start"
    case stop           = "stop"
    case restart        = "restart"
    case reload         = "reload"
    case status         = "status"
    case connections    = "connections"
}
class UserCommand {
    var command: Command = .start
    func get() {
        let argCount = CommandLine.argc
        let arguments = CommandLine.arguments
        print(argCount)
        for argument in arguments {
            print(argument)
        }
    }
}
