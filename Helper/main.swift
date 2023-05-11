//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import Server

let server = Server()
do {
    try server.start()
} catch {
    exit(0)
}
