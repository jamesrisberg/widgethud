import Foundation
import XCTest
@testable import widgetHUDKit

final class AgendaTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-01 (a Thursday) at `hour`:`minute` UTC, plus `day` days.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_790_812_800 + Double(day) * 86_400 + Double(hour) * 3600 + Double(minute) * 60)
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, calendar: String = "Work") -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, calendar: calendar)
    }

    func testUpcomingDropsEndedEventsAndPutsAllDayFirstWithinADay() {
        let now = at(0, 10)
        let events = [
            event("ended", at(0, 8), at(0, 9)),
            event("later", at(0, 15), at(0, 16)),
            event("now", at(0, 9, 30), at(0, 10, 30)),
            event("allday", at(0, 0), at(1, 0), allDay: true),
            event("tomorrow", at(1, 9), at(1, 10)),
            event("beyond", at(5, 9), at(5, 10)),
        ]
        let horizon = Agenda.horizon(days: 3, now: now, calendar: calendar)
        XCTAssertEqual(horizon, at(3, 0))
        XCTAssertEqual(Agenda.upcoming(events, now: now, until: horizon, calendar: calendar).map(\.id),
                       ["allday", "now", "later", "tomorrow"])
        XCTAssertEqual(Agenda.next(Agenda.upcoming(events, now: now, until: horizon, calendar: calendar))?.id, "now",
                       "the one-event view prefers a timed event")
        XCTAssertEqual(Agenda.next([event("allday", at(0, 0), at(1, 0), allDay: true)])?.id, "allday")
        XCTAssertNil(Agenda.next([]))
    }

    func testDaysGroupsByDayKeepsTodayAndRepeatsMultiDayEvents() {
        let now = at(0, 20)
        let events = [
            event("trip", at(1, 0), at(3, 0), allDay: true),
            event("dinner", at(1, 19), at(1, 21)),
            event("ended", at(0, 8), at(0, 9)),
        ]
        let days = Agenda.days(events, now: now, days: 4, calendar: calendar)
        XCTAssertEqual(days.map(\.date), [at(0, 0), at(1, 0), at(2, 0)], "today kept though empty; day 3 has nothing")
        XCTAssertEqual(days[0].events, [])
        XCTAssertEqual(days[1].events.map(\.id), ["trip", "dinner"])
        XCTAssertEqual(days[2].events.map(\.id), ["trip"])
    }

    func testTitlesAndWhen() {
        let now = at(0, 10)
        XCTAssertEqual(Agenda.dayTitle(at(0, 0), now: now, calendar: calendar), "Today")
        XCTAssertEqual(Agenda.dayTitle(at(1, 0), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(Agenda.dayTitle(at(2, 0), now: now, calendar: calendar), "Sat 3 Oct")
        let f = TimeFormat.twentyFour
        XCTAssertEqual(Agenda.when(event("a", at(0, 9), at(0, 11)), now: now, format: f, calendar: calendar), "Now")
        XCTAssertEqual(Agenda.when(event("b", at(0, 10, 25), at(0, 11)), now: now, format: f, calendar: calendar), "In 25 min")
        XCTAssertEqual(Agenda.when(event("c", at(0, 14), at(0, 15)), now: now, format: f, calendar: calendar), "14:00")
        XCTAssertEqual(Agenda.when(event("d", at(1, 9), at(1, 10)), now: now, format: .twelve, calendar: calendar), "Tomorrow 9:00 AM")
        XCTAssertEqual(Agenda.when(event("e", at(2, 9), at(2, 10)), now: now, format: f, calendar: calendar), "Sat 9:00")
        XCTAssertEqual(Agenda.when(event("f", at(0, 0), at(1, 0), allDay: true), now: now, format: f, calendar: calendar), "All day")
        XCTAssertEqual(Agenda.when(event("g", at(1, 0), at(2, 0), allDay: true), now: now, format: f, calendar: calendar), "Tomorrow, all day")
        XCTAssertEqual(Agenda.span(event("h", at(0, 14), at(0, 15)), format: f, calendar: calendar), "14:00")
        XCTAssertEqual(Agenda.span(event("i", at(0, 0), at(1, 0), allDay: true), format: f, calendar: calendar), "All day")
    }

    func testSampleEventsAreUpcoming() {
        let now = Date()
        let events = SampleData.events(now: now)
        XCTAssertFalse(Agenda.upcoming(events, now: now, until: Agenda.horizon(days: 3, now: now)).isEmpty)
        XCTAssertEqual(Set(events.map(\.id)).count, events.count, "unique ids")
    }
}
