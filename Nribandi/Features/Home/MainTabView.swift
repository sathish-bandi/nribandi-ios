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
            ServiceRequestsView()
                .tabItem { Label("Requests", systemImage: "wrench.and.screwdriver.fill") }
            if showsOpsTabs {
                EnquiriesView()
                    .tabItem { Label("Enquiries", systemImage: "bubble.left.and.bubble.right.fill") }
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
}
