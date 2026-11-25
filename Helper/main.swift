//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import Server

#if BETA
let server = Server(isBeta: true)
#else
let server = Server(isBeta: false)
#endif
do {
    try server.start()
} catch {
    exit(0)
}
