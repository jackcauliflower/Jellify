//
//  ResultSet.swift
//  FinTune
//
//  Created by Jack Caulfield on 10/10/21.
//

import Foundation

public struct ResultSet<T:Codable>: Codable {
    let items: [T]
    let totalRecordCount, startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}
