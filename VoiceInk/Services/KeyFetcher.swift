import Foundation

class KeyFetcher {
    static let shared = KeyFetcher()
    
    // Worker URLs
    private let baseURL = "https://voiceink-key-server.prakashjoshipax.workers.dev"
    private let argmaxURL: URL
    private let huggingFaceURL: URL
    private let polarOrgIdURL: URL
    private let polarApiTokenURL: URL
    private let polarBaseURL: URL
    
    private let apiAuthSecret = "voiceink-api-key"
    private let headerName = "x-api-auth"
    
    private init() {
        self.argmaxURL = URL(string: "\(baseURL)/argmax")!
        self.huggingFaceURL = URL(string: "\(baseURL)/huggingface")!
        self.polarOrgIdURL = URL(string: "\(baseURL)/polar-org-id")!
        self.polarApiTokenURL = URL(string: "\(baseURL)/polar-api-token")!
        self.polarBaseURL = URL(string: "\(baseURL)/polar-base-url")!
    }
    
    func fetchArgmaxKey(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: argmaxURL)
        request.setValue(apiAuthSecret, forHTTPHeaderField: headerName)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let key = String(data: data, encoding: .utf8),
                (response as? HTTPURLResponse)?.statusCode == 200
            else {
                completion(nil)
                return
            }
            completion(key)
        }
        task.resume()
    }
    
    func fetchHuggingFaceKey(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: huggingFaceURL)
        request.setValue(apiAuthSecret, forHTTPHeaderField: headerName)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let key = String(data: data, encoding: .utf8),
                (response as? HTTPURLResponse)?.statusCode == 200
            else {
                completion(nil)
                return
            }
            completion(key)
        }
        task.resume()
    }
    
    func fetchPolarOrganizationId(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: polarOrgIdURL)
        request.setValue(apiAuthSecret, forHTTPHeaderField: headerName)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let orgId = String(data: data, encoding: .utf8),
                (response as? HTTPURLResponse)?.statusCode == 200
            else {
                completion(nil)
                return
            }
            completion(orgId)
        }
        task.resume()
    }
    
    func fetchPolarApiToken(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: polarApiTokenURL)
        request.setValue(apiAuthSecret, forHTTPHeaderField: headerName)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let token = String(data: data, encoding: .utf8),
                (response as? HTTPURLResponse)?.statusCode == 200
            else {
                completion(nil)
                return
            }
            completion(token)
        }
        task.resume()
    }
    
    func fetchPolarBaseURL(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: polarBaseURL)
        request.setValue(apiAuthSecret, forHTTPHeaderField: headerName)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                let data = data,
                let baseURL = String(data: data, encoding: .utf8),
                (response as? HTTPURLResponse)?.statusCode == 200
            else {
                completion(nil)
                return
            }
            completion(baseURL)
        }
        task.resume()
    }
} 