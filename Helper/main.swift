//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import Server

class Delegate: ServerDelegate {
    func thereIsNothingToDo() {
        exit(0)
    }
}

let delegate = Delegate()
let server = Server()
server.delegate = delegate
do {
    try await server.start()
} catch {
    exit(0)
}
