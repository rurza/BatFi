//
//  ScreenParametersClient.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import Foundation

struct ScreenParametersClient {
    var screenDidChangeParameters: () -> AsyncStream<Void>
}
