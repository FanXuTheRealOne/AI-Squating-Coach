//
//  BedrockService.swift
//  camera
//

import Foundation

class BedrockService {
    private let apiURL = APIConfig.bedrockAPI
    
    func sendMessage(_ message: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: apiURL) else {
            completion(.failure(NSError(domain: "BedrockService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["message": message]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ 网络错误: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP 状态码: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("❌ 没有收到数据")
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "BedrockService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                }
                return
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 原始响应: \(responseString)")
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ JSON 解析成功，所有字段: \(json.keys)")
                    
                    if let codeText = json["code"] as? String {
                        print("✅ 找到 code 字段")
                        DispatchQueue.main.async {
                            completion(.success(codeText))
                        }
                    } else if let responseText = json["response"] as? String {
                        print("✅ 找到 response 字段")
                        DispatchQueue.main.async {
                            completion(.success(responseText))
                        }
                    } else if let bodyText = json["body"] as? String {
                        print("✅ 找到 body 字段（字符串格式）")
                        // body 可能是字符串化的 JSON，需要再次解析
                        if let bodyData = bodyText.data(using: .utf8),
                           let bodyJson = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                           let messageText = bodyJson["message"] as? String {
                            print("✅ 从 body 中解析出 message 字段")
                            DispatchQueue.main.async {
                                completion(.success(messageText))
                            }
                        } else {
                            // 如果 body 不是 JSON 格式，直接返回
                            print("⚠️ body 不是 JSON 格式，直接返回字符串")
                            DispatchQueue.main.async {
                                completion(.success(bodyText))
                            }
                        }
                    } else if let messageText = json["message"] as? String {
                        print("✅ 找到 message 字段")
                        DispatchQueue.main.async {
                            completion(.success(messageText))
                        }
                    } else {
                        print("❌ 未找到预期的响应字段，完整 JSON: \(json)")
                        let errorMsg = "Response format error, available fields: \(json.keys.joined(separator: ", "))"
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "BedrockService", code: -3, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                        }
                    }
                } else {
                    print("❌ JSON 不是字典格式")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("尝试作为字符串返回: \(responseString)")
                        DispatchQueue.main.async {
                            completion(.success(responseString))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "BedrockService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response"])))
                        }
                    }
                }
            } catch {
                print("❌ JSON 解析异常: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("尝试作为字符串返回: \(responseString)")
                    DispatchQueue.main.async {
                        completion(.success(responseString))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }
}

