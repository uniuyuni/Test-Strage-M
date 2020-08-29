//
//  Util.swift
//  Test Strage M
//
//  Created by うに on 2020/08/27.
//  Copyright © 2020 うに. All rights reserved.
//

import Foundation

func removeOptionalString(_ str: String) -> String {
    var temp = str
    
    if let range = temp.range(of: "Optional(\"") {
        temp.removeSubrange(range)
    }
    if let range = temp.range(of: "\")") {
        temp.removeSubrange(range)
    }
    
    return temp
}

func toStringByteFormat(_ byte: Int ) -> (value: Double, unit: String) {
    if byte < 1024 {
        return (Double(byte), "B")
    }
    if byte < 1024*1024 {
        return (Double(byte)/1024, "KB")
    }
    if byte < 1024*1024*1024 {
        return (Double(byte)/1024/1024, "MB")
    }
    if byte < 1024*1024*1024*1024 {
        return (Double(byte)/1024/1024/1024, "GB")
    }
    return (Double(byte)/1024/1024/1024/1024, "TB")
}

func toStringCanmaFormat(_ v: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = NumberFormatter.Style.decimal
    formatter.groupingSeparator = ","
    formatter.groupingSize = 3
    
    return formatter.string(from: NSNumber(value: v)) ?? ""
}
