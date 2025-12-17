//
//  CameraService.swift
//  camera
//
//  Created by xufan on 2025/9/27.
//
import AVFoundation
import Photos

class CameraService: NSObject {
    // 核心会话：连接输入和输出
    var session: AVCaptureSession?
    
    // 照片输出：用于捕获照片
    let output = AVCapturePhotoOutput()
    
    // 视频预览层：显示实时图像
    let previewLayer = AVCaptureVideoPreviewLayer()
    
    // 委托：用于处理照片捕获完成事件 (不是本教程的重点，但结构需要)
    var photoDelegate: AVCapturePhotoCaptureDelegate?

    // 录像输出：用于录制视频到文件
    private let movieOutput = AVCaptureMovieFileOutput()
    private var onRecordingFinished: ((URL?, Error?) -> Void)?
    private(set) var isRecording: Bool = false
    
    override init() {
        super.init()
        print("📹 CameraService init")
        // 确保初始化是轻量级的，不进行任何阻塞操作
    }


    // 检查权限并设置会话
    func setupAndStartSession(completion: @escaping (Error?) -> Void) {
        checkPermissions { error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(error)
                }
                return
            }
            
            // 权限检查通过，开始配置摄像头
            self.configureSession()
            
            // 确保在主线程上启动会话
            DispatchQueue.main.async {
                guard let session = self.session else {
                    completion(NSError(domain: "CameraService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to configure camera session"]))
                    return
                }
                
                session.startRunning()
                completion(nil)
            }
        }
    }

    // 停止会话，离开摄像头页面时调用
    func stopSession() {
        DispatchQueue.main.async {
            self.session?.stopRunning()
        }
    }

    // 开始录像，保存到临时文件，结束后保存到相册
    func startRecording(completion: @escaping (Error?) -> Void, finished: @escaping (URL?, Error?) -> Void) {
        guard let session = session, session.isRunning else {
            completion(NSError(domain: "CameraService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Session not running"]))
            return
        }
        guard !movieOutput.isRecording else {
            completion(NSError(domain: "CameraService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Already recording"]))
            return
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        onRecordingFinished = finished
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
        completion(nil)
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func checkPermissions(completion: @escaping (Error?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // 首次请求权限
            AVCaptureDevice.requestAccess(for: .video) { granted in
                // 确保在主线程上执行回调
                DispatchQueue.main.async {
                    guard granted else {
                        // 用户拒绝权限，返回错误 (实际应用中应返回自定义错误)
                        completion(NSError(domain: "CameraService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied"]))
                        return
                    }
                    completion(nil)
                }
            }
        case .denied, .restricted:
            // 权限被拒绝或受限
            completion(NSError(domain: "CameraService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Camera access restricted or denied"]))
        case .authorized:
            // 权限已授权
            completion(nil)
        @unknown default:
            break
        }
    }
    
    private func configureSession() {
        // 1. 创建会话
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // 2. 设置输入：默认后置摄像头
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ 无法找到后置摄像头")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            session.beginConfiguration()
            
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                print("❌ 无法添加相机输入")
                session.commitConfiguration()
                return
            }
            
            // 3. 设置输出：用于拍照
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            // 3.1 添加录像输出
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            
            session.commitConfiguration()
            
            // 4. 配置预览层 (需要在主线程上设置)
            DispatchQueue.main.async {
                self.previewLayer.session = session
                self.previewLayer.videoGravity = .resizeAspectFill
            }
            
            self.session = session
            
        } catch {
            print("❌ 设置相机输入错误: \(error.localizedDescription)")
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        isRecording = false
        guard error == nil else {
            onRecordingFinished?(nil, error)
            onRecordingFinished = nil
            return
        }
        saveVideoToPhotoLibrary(fileURL: outputFileURL) { saveError in
            if let saveError = saveError {
                self.onRecordingFinished?(nil, saveError)
            } else {
                self.onRecordingFinished?(outputFileURL, nil)
            }
            self.onRecordingFinished = nil
        }
    }
    
    private func saveVideoToPhotoLibrary(fileURL: URL, completion: @escaping (Error?) -> Void) {
        let handler: (PHAuthorizationStatus) -> Void = { status in
            guard status == .authorized || status == .limited else {
                completion(NSError(domain: "CameraService", code: 12, userInfo: [NSLocalizedDescriptionKey: "Photo Library permission denied"]))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }, completionHandler: { success, error in
                completion(error)
            })
        }
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async { handler(status) }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async { handler(status) }
            }
        }
    }
}

    



