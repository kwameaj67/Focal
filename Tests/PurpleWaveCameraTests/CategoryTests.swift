//
//  CategoryTests.swift
//  PurpleWaveCameraTests
//

import XCTest
@testable import PurpleWaveCameraCore

final class CategoryTests: XCTestCase {

    func testConvenienceInitUsesTitleAsID() {
        let category = PWCategory("Profile")
        XCTAssertEqual(category.id, "Profile")
        XCTAssertEqual(category.title, "Profile")
    }

    func testExplicitInitKeepsSeparateIDAndTitle() {
        let category = PWCategory(id: "AMKT", title: "Profile")
        XCTAssertEqual(category.id, "AMKT")
        XCTAssertEqual(category.title, "Profile")
    }

    func testEqualityConsidersBothFields() {
        XCTAssertEqual(PWCategory(id: "a", title: "A"), PWCategory(id: "a", title: "A"))
        XCTAssertNotEqual(PWCategory(id: "a", title: "A"), PWCategory(id: "a", title: "B"))
    }

    func testHashableInSet() {
        let set: Set<PWCategory> = [PWCategory("A"), PWCategory("A"), PWCategory("B")]
        XCTAssertEqual(set.count, 2)
    }
}
