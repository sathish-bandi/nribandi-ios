import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            if showsOpsTabs {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            }
            PropertiesView()
                .tabItem { Label("Properties", systemImage: "building.2.fill") }
            if showsPeopleTab {
                PeopleView()
                    .tabItem { Label(peopleTabTitle, systemImage: "person.2.fill") }
            }
            ServiceRequestsView()
                .tabItem { Label("Requests", systemImage: "wrench.and.screwdriver.fill") }
            if showsOpsTabs {
                OpsHubView()
                    .tabItem { Label("Ops", systemImage: "square.grid.2x2.fill") }
            }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(NriTheme.teal)
    }

    private var showsOpsTabs: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    private var showsPeopleTab: Bool { showsOpsTabs }

    private var peopleTabTitle: String {
        session.user?.role == .EMPLOYEE ? "Tenants" : "People"
    }
}
