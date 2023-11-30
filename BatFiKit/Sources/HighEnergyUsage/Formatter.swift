//
//  Formatter.swift
//  
//
//  Created by Adam on 25/10/2023.
//

import Foundation

let energyImpactFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
}()
