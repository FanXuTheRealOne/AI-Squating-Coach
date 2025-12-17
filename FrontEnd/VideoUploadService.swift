//
//  VideoUploadService.swift
//  camera
//

import Foundation
import Photos

class VideoUploadService {
    private let presignedUrlAPI = APIConfig.presignedUrlAPI
    private let videoAnalysisAPI = APIConfig.videoAnalysisAPI
    
    func uploadAndAnalyzeVideo(videoURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let videoData = try? Data(contentsOf: videoURL) else {
            completion(.failure(NSError(domain: "VideoUploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to read video file"])))
            return
        }
        
        // 使用 S3 URI 方式，支持最大 1GB 的视频文件
        let maxSize = 1024 * 1024 * 1024  // 1GB (Nova 模型 S3 URI 方式的最大限制)
        guard videoData.count <= maxSize else {
            let sizeInMB = Double(videoData.count) / 1024 / 1024
            completion(.failure(NSError(domain: "VideoUploadService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video file too large (\(String(format: "%.1f", sizeInMB))MB), maximum limit 1GB"])))
            return
        }
        
        print("📤 开始上传流程，视频大小: \(videoData.count) bytes")
        
        // 1. 获取预签名 URL
        getPresignedUrl { [weak self] result in
            switch result {
            case .success(let (presignedUrl, s3Key)):
                print("✅ 获取到预签名 URL，s3Key: \(s3Key)")
                // 2. 直接上传到 S3
                self?.uploadToS3(videoData: videoData, presignedUrl: presignedUrl, s3Key: s3Key, completion: completion)
            case .failure(let error):
                print("❌ 获取预签名 URL 失败: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    private func getPresignedUrl(completion: @escaping (Result<(String, String), Error>) -> Void) {
        guard let url = URL(string: presignedUrlAPI) else {
            completion(.failure(NSError(domain: "VideoUploadService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("📤 请求预签名 URL: \(presignedUrlAPI)")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ 网络错误: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "VideoUploadService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            print("📡 HTTP 状态码: \(httpResponse.statusCode)")
            print("📡 HTTP 响应头: \(httpResponse.allHeaderFields)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMsg = "HTTP error: \(httpResponse.statusCode)"
                print("❌ \(errorMsg)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("📥 错误响应内容: \(responseString)")
                }
                completion(.failure(NSError(domain: "VideoUploadService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "VideoUploadService", code: -5, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 原始响应: \(responseString)")
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ 响应不是 JSON 格式")
                    completion(.failure(NSError(domain: "VideoUploadService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Response format error"])))
                    return
                }
                
                print("✅ JSON 解析成功，所有字段: \(json.keys)")
                
                var presignedUrl: String?
                var s3Key: String?
                
                if let bodyString = json["body"] as? String,
                   let bodyData = bodyString.data(using: .utf8),
                   let bodyJson = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    presignedUrl = bodyJson["presignedUrl"] as? String
                    s3Key = bodyJson["s3Key"] as? String
                } else if let bodyDict = json["body"] as? [String: Any] {
                    presignedUrl = bodyDict["presignedUrl"] as? String
                    s3Key = bodyDict["s3Key"] as? String
                } else {
                    presignedUrl = json["presignedUrl"] as? String
                    s3Key = json["s3Key"] as? String
                }
                
                guard let url = presignedUrl, let key = s3Key else {
                    completion(.failure(NSError(domain: "VideoUploadService", code: -7, userInfo: [NSLocalizedDescriptionKey: "presignedUrl or s3Key not found"])))
                    return
                }
                
                completion(.success((url, key)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func uploadToS3(videoData: Data, presignedUrl: String, s3Key: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: presignedUrl) else {
            completion(.failure(NSError(domain: "VideoUploadService", code: -8, userInfo: [NSLocalizedDescriptionKey: "Invalid presigned URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = videoData
        
        print("📤 开始上传到 S3，大小: \(videoData.count) bytes")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ S3 上传错误: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "VideoUploadService", code: -9, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            print("📡 S3 上传 HTTP 状态码: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMsg = "S3 upload failed: HTTP \(httpResponse.statusCode)"
                print("❌ \(errorMsg)")
                completion(.failure(NSError(domain: "VideoUploadService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                return
            }
            
            print("✅ 视频已成功上传到 S3: \(s3Key)")
            // 3. 上传成功后，调用分析 API
            self.analyzeVideo(s3Key: s3Key, completion: completion)
        }.resume()
    }
    
    private func analyzeVideo(s3Key: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: videoAnalysisAPI) else {
            completion(.failure(NSError(domain: "VideoUploadService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["s3Key": s3Key]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("📤 开始调用视频分析 API: \(videoAnalysisAPI)")
        print("📤 s3Key: \(s3Key)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ 网络错误: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "VideoUploadService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            print("📡 分析 API HTTP 状态码: \(httpResponse.statusCode)")
            
            guard let data = data else {
                completion(.failure(NSError(domain: "VideoUploadService", code: -6, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 分析 API 原始响应: \(responseString)")
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ 响应不是 JSON 格式")
                    completion(.failure(NSError(domain: "VideoUploadService", code: -7, userInfo: [NSLocalizedDescriptionKey: "Response format error"])))
                    return
                }
                
                print("✅ JSON 解析成功，所有字段: \(json.keys)")
                
                var analysis: String?
                
                // 尝试多种解析方式
                if let bodyString = json["body"] as? String {
                    print("📝 body 是字符串，尝试解析...")
                    if let bodyData = bodyString.data(using: .utf8),
                       let bodyJson = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                        print("✅ body 字符串解析成功，字段: \(bodyJson.keys)")
                        analysis = bodyJson["Squat_analysis"] as? String
                    }
                } else if let bodyDict = json["body"] as? [String: Any] {
                    print("📝 body 是字典，字段: \(bodyDict.keys)")
                    analysis = bodyDict["Squat_analysis"] as? String
                } else if let directAnalysis = json["Squat_analysis"] as? String {
                    print("📝 直接从根级别获取 Squat_analysis")
                    analysis = directAnalysis
                }
                
                if let analysis = analysis {
                    print("✅ 成功获取分析结果")
                    completion(.success(analysis))
                } else {
                    print("❌ 无法找到 Squat_analysis 字段")
                    print("❌ 完整 JSON: \(json)")
                    completion(.failure(NSError(domain: "VideoUploadService", code: -7, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response, analysis result not found"])))
                }
            } catch {
                print("❌ JSON 解析异常: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
}

