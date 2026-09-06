import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var environment: AppEnvironment
    let session: SessionStore
    let api: APIClient

    init() {
        let env = AppEnvironment.loadSaved()
        let session = SessionStore()
        self.environment = env
        self.session = session
        self.api = APIClient(environment: env, session: session)
        session.bind(api: api)
    }

    func switchEnvironment(_ env: AppEnvironment) async {
        await session.logout()
        environment = env
        env.save()
        await api.updateEnvironment(env)
    }
}
