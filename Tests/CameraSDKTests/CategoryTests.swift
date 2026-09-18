//
//  CategoryTests.swift
//  CameraSDKTests
//

import XCTest
@testable import CameraSDKCore

final class CategoryTests: XCTestCase {

    func testConvenienceInitUsesTitleAsID() {
        let category = CSCategory("Profile")
        XCTAssertEqual(category.id, "Profile")
        XCTAssertEqual(category.title, "Profile")
    }

    func testExplicitInitKeepsSeparateIDAndTitle() {
        let category = CSCategory(id: "AMKT", title: "Profile")
        XCTAssertEqual(category.id, "AMKT")
        XCTAssertEqual(category.title, "Profile")
    }

    func testEqualityConsidersBothFields() {
        XCTAssertEqual(CSCategory(id: "a", title: "A"), CSCategory(id: "a", title: "A"))
        XCTAssertNotEqual(CSCategory(id: "a", title: "A"), CSCategory(id: "a", title: "B"))
    }

    func testHashableInSet() {
        let set: Set<CSCategory> = [CSCategory("A"), CSCategory("A"), CSCategory("B")]
        XCTAssertEqual(set.count, 2)
    }
}
