//
//  MenuTooltipPlacementTests.swift
//  BatFi
//
//  Unit tests for where BatFi's own menu tooltip goes on screen.
//

import CoreGraphics
import Testing

@testable import AppShared

@Suite struct MenuTooltipPlacementTests {
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    static let size = CGSize(width: 200, height: 40)
    let gap = MenuTooltipPlacement.gap

    private func frame(below element: CGRect, size: CGSize = size, within screen: CGRect = screen) -> CGRect {
        MenuTooltipPlacement.frame(for: size, below: element, within: screen)
    }

    @Test func itSitsJustBelowTheElementCentredUnderIt() {
        let element = CGRect(x: 600, y: 500, width: 100, height: 20)
        #expect(frame(below: element) == CGRect(x: 550, y: 500 - gap - 40, width: 200, height: 40))
    }

    @Test func itGoesAboveWhereTheScreenEndsBelow() {
        let element = CGRect(x: 600, y: 30, width: 100, height: 20)
        #expect(frame(below: element) == CGRect(x: 550, y: 50 + gap, width: 200, height: 40))
    }

    @Test func itGoesBelowWhenItFitsExactly() {
        let element = CGRect(x: 600, y: 40 + gap, width: 100, height: 20)
        #expect(frame(below: element).minY == 0)
    }

    @Test func itSlidesLeftToStayOnTheScreen() {
        let element = CGRect(x: 1400, y: 500, width: 30, height: 20)
        #expect(frame(below: element).maxX == 1440)
    }

    @Test func itSlidesRightToStayOnTheScreen() {
        let element = CGRect(x: 5, y: 500, width: 30, height: 20)
        #expect(frame(below: element).minX == 0)
    }

    @Test func itStaysOnASecondScreenLeftOfAndBelowTheMainOne() {
        let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let element = CGRect(x: -1910, y: -280, width: 30, height: 20)
        let placed = frame(below: element, within: screen)
        #expect(placed.minX == -1920)
        #expect(placed.minY == -260 + gap)
    }

    @Test func oneThatFitsNeitherBelowNorAboveStaysOnTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 100)
        let element = CGRect(x: 600, y: 40, width: 100, height: 20)
        let placed = frame(below: element, size: CGSize(width: 200, height: 60), within: screen)
        #expect(placed.minY >= 0)
        #expect(placed.maxY <= 100)
    }

    @Test func oneBelowItsElementIsOnTheSideBelow() {
        let element = CGRect(x: 600, y: 500, width: 100, height: 20)
        #expect(MenuTooltipPlacement.side(of: frame(below: element), from: element) == .below)
    }

    @Test func oneFlippedAboveItsElementIsOnTheSideAbove() {
        let element = CGRect(x: 600, y: 30, width: 100, height: 20)
        #expect(MenuTooltipPlacement.side(of: frame(below: element), from: element) == .above)
    }

    @Test func oneTallerThanTheScreenStartsAtItsBottom() {
        let element = CGRect(x: 600, y: 400, width: 100, height: 20)
        let placed = frame(below: element, size: CGSize(width: 200, height: 2000))
        #expect(placed.minY == 0)
    }
}
