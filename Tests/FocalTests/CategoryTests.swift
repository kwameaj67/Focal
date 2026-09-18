//
//  CategoryTests.swift
//  FocalTests
//

import XCTest
@testable import FocalCore

final class CategoryTests: XCTestCase {

    func testConvenienceInitUsesTitleAsID() {
        let category = FCCategory("Profile")
        XCTAssertEqual(category.id, "Profile")
        XCTAssertEqual(category.title, "Profile")
    }

    func testExplicitInitKeepsSeparateIDAndTitle() {
        let category = FCCategory(id: "AMKT", title: "Profile")
        XCTAssertEqual(category.id, "AMKT")
        XCTAssertEqual(category.title, "Profile")
    }

    func testEqualityConsidersBothFields() {
        XCTAssertEqual(FCCategory(id: "a", title: "A"), FCCategory(id: "a", title: "A"))
        XCTAssertNotEqual(FCCategory(id: "a", title: "A"), FCCategory(id: "a", title: "B"))
    }

    func testHashableInSet() {
        let set: Set<FCCategory> = [FCCategory("A"), FCCategory("A"), FCCategory("B")]
        XCTAssertEqual(set.count, 2)
    }
}
