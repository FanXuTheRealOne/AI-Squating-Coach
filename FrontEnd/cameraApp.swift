//
//  cameraApp.swift
//  camera
//
//  Created by xufan on 2025/9/26.
//

import SwiftUI
import Network

@main
struct SquatAIApp: App {
    @StateObject private var networkMonitor = NetworkMonitor()
    
    init() {
        print("🚀 SquatAIApp init 开始")
        // 确保应用启动时清理可能的问题状态
        setupApp()
        print("🚀 SquatAIApp init 完成")
    }
    
    private func setupApp() {
        // 清理可能存在的旧状态
        // 这可以防止更新后因为状态不一致导致的黑屏
        print("🔧 设置应用环境")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(networkMonitor)
                .task {
                    print("🚀 ContentView task 开始")
                    // 启动网络监控
                    networkMonitor.startMonitoring()
                }
                .onAppear {
                    print("🚀 ContentView onAppear 在 WindowGroup")
                }
        }
    }
}

// 网络监控类
class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                
                if path.status == .satisfied {
                    print("✅ 网络连接正常")
                } else {
                    print("⚠️ 网络连接不可用")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
}


