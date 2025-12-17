//
//  ContentView.swift
//  camera
//
//  Created by xufan on 2025/9/26.
//

import SwiftUI
import PhotosUI
import Network
import UIKit

// 消息模型
struct Message: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}

// 清理并美化 AI 输出，移除 **，替换为 bullet，并高亮错误
private func formatAIOutput(_ text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    var cleaned: [String] = []
    
    for line in lines {
        var l = line.trimmingCharacters(in: .whitespaces)
        if l.isEmpty {
            cleaned.append("")
            continue
        }
        // 移除 markdown 星号
        l = l.replacingOccurrences(of: "**", with: "")
        l = l.replacingOccurrences(of: "__", with: "")
        
        // bullet
        if l.hasPrefix("- ") {
            l = "• " + l.dropFirst(2)
        }
        
        // 高亮错误关键词
        let lower = l.lowercased()
        if lower.contains("incorrect") || lower.contains("valgus") || lower.contains("error") {
            l = "🚩 " + l
        }
        
        cleaned.append(l)
    }
    
    // 合并，保留空行
    return cleaned.joined(separator: "\n")
}


struct ContentView: View {
    // 应用导航状态
    @State private var isPresentingCamera: Bool = false
    @State private var showPermissionAlert: Bool = false
    @State private var permissionMessage: String = ""
    
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var messages: [Message] = []
    @FocusState private var isTextFieldFocused: Bool
    @State private var hasTappedInputArea: Bool = false // 跟踪用户是否点击过输入框区域
    @State private var selectedVideo: PhotosPickerItem?
    @State private var showVideoPicker: Bool = false
    @State private var isUploadingVideo: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var showNetworkAlert: Bool = false
    @EnvironmentObject var networkMonitor: NetworkMonitor
    
    // 检查是否首次启动
    private var isFirstLaunch: Bool {
        get {
            !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        }
    }
    
    private func markAsLaunched() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
    
    // 单例相机管理器，供相机页使用
    @StateObject private var cameraManager = CameraManager()
    private let bedrockService = BedrockService()
    private let videoUploadService = VideoUploadService()
    
    init() {
        print("🔧 ContentView init 开始")
        // 确保初始化是轻量级的
        print("🔧 ContentView init 完成")
    }
    
    private var showChatView: Bool {
        // 当输入框聚焦、有消息、或用户点击过输入框区域时显示聊天视图
        isTextFieldFocused || !messages.isEmpty || hasTappedInputArea
    }

    
    // 重置状态，防止更新后状态不一致导致黑屏
    private func resetStateIfNeeded() {
        // 如果 isLoading 或 isUploadingVideo 异常地保持为 true，重置它们
        // 这通常发生在代码更新后，旧的状态数据可能导致问题
        if isLoading && !hasAppeared {
            print("⚠️ 检测到异常状态，重置 isLoading")
            isLoading = false
        }
        if isUploadingVideo && selectedVideo == nil {
            print("⚠️ 检测到异常状态，重置 isUploadingVideo")
            isUploadingVideo = false
        }
        // 确保 selectedVideo 在更新后不会导致问题
        if selectedVideo != nil && !hasAppeared {
            print("⚠️ 检测到残留的 selectedVideo，清除")
            selectedVideo = nil
        }


    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.96, green: 0.96, blue: 0.97)
                .ignoresSafeArea()
                .onAppear {
                    print("🎨 ContentView body 渲染")
                    // 确保状态正确初始化
                    resetStateIfNeeded()
                }
            
            if showChatView {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showChatView)
                
                ZStack(alignment: .topLeading) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            ZStack(alignment: .topLeading) {
                                LazyVStack(spacing: 12) {
                                    ForEach(messages) { message in
                                        MessageBubble(message: message)
                                            .id(message.id)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 60)
                                .padding(.bottom, 180)
                                
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .textSelection(.enabled)
                        .onChange(of: messages.count) { count in
                            if let lastMessage = messages.last {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Button(action: {
                            goBack()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                                .frame(minWidth: 60, minHeight: 60)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    
                    // 底部快捷选项，键盘弹出或有输入/消息时隐藏
                    if showQuickOptions {
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                QuickChip(emoji: "🩻", title: "(Rehab) Ask a physio how to avoid injuries") {
                                    inputText = "How do I adjust my squat to avoid injuries? (asked to a professional physio)"
                                    isTextFieldFocused = true
                                }
                                QuickChip(emoji: "🏋", title: "(Strength) Ask a world champion for a squat plan") {
                                    inputText = "Give me a world champion-level squat plan to get stronger."
                                    isTextFieldFocused = true
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100) // 悬浮在输入框上方
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: showQuickOptions)
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Spacer()
                                    .frame(height: 60)
                                    .id("top")
                                
                                VStack(spacing: 16) {
                                    Text("Your Personal AI\nSquat Trainer")
                                        .font(.system(size: 36, weight: .semibold, design: .default))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                                        .tracking(-0.5)
                                    
                                    Text("Perfect your form and maximize your results with personalized AI feedback.")
                                        .font(.system(size: 16, weight: .regular, design: .default))
                                        .foregroundColor(Color(red: 0.43, green: 0.43, blue: 0.45))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                        .lineLimit(nil)
                                }
                                
                                Spacer()
                                    .frame(height: 32)
                                
                                VStack(spacing: 12) {
                                    CircleProgressView()
                                        .frame(width: 240, height: 240)
                                    
                                    Button(action: {
                                        UserDefaults.standard.set(0, forKey: "lastNovaScore")
                                        NotificationCenter.default.post(name: .init("lastNovaScoreUpdated"), object: nil)
                                    }) {
                                        Text("Reset Score")
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundColor(Color(red: 0.40, green: 0.40, blue: 0.45))
                                            .tracking(0.5)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Spacer()
                                    .frame(height: 32)
                                
                Button(action: {
                    requestPermissionAndStart()
                }) {
                                    Text("Start Squatting Now")
                                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(Color(red: 0.98, green: 0.45, blue: 0.09))
                                        .cornerRadius(9999)
                                        .padding(.horizontal, 24)
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                                    .frame(minHeight: 120)
                            }
                        }
                        .onChange(of: isTextFieldFocused) { focused in
                            if focused {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("top", anchor: .top)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: showChatView)
            }
            
            // 输入框区域 - 模仿 ChatGPT 设计
            VStack(spacing:1) {
                // 输入框内容
                HStack(spacing: 12) {
                    // 左侧视频按钮
                    Button(action: {
                        print("🎬 视频按钮被点击")
                        showVideoPicker = true
                        print("🎬 showVideoPicker = \(showVideoPicker)")
                    }) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(Color(red: 0.98, green: 0.45, blue: 0.09))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(isLoading)
                    
                    // 输入框 - 扁平设计
                    HStack(spacing: 8) {
                        TextField("Ask me anything about squats", text: $inputText)
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .focused($isTextFieldFocused)
                            .onTapGesture {
                                hasTappedInputArea = true
                                isTextFieldFocused = true
                            }
                        
                        // 右侧发送按钮
                        Button(action: {
                            if selectedVideo != nil {
                                uploadVideo()
                            } else {
                                sendMessage()
                            }
                        }) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.98, green: 0.45, blue: 0.09)))
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color(red: 0.98, green: 0.45, blue: 0.09))
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .disabled((inputText.isEmpty && selectedVideo == nil) || isLoading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                Color.white
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            )
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .fullScreenCover(isPresented: $isPresentingCamera) {
            CameraScreen(cameraManager: cameraManager) {
                cameraManager.stopCamera()
                DispatchQueue.main.async {
                isPresentingCamera = false
                }
            }
        }
        .alert("Camera Permission", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(permissionMessage)
        }
        .onAppear {
            print("👁️ ContentView onAppear")
            hasAppeared = true
            // 确保所有状态正确初始化
            resetStateIfNeeded()
            
            // 只在首次启动时检查网络状态
            if isFirstLaunch {
                print("📱 首次启动，检查网络状态")
                markAsLaunched()
                
                // 延迟检查，确保网络监控已启动
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !networkMonitor.isConnected {
                        showNetworkAlert = true
                    }
                }
            }
        }
        .alert("Network Connection", isPresented: $showNetworkAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please check your internet connection. The app requires network access to analyze videos and answer questions.")
        }
        .onDisappear {
            print("👁️ ContentView onDisappear")
        }
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideo, matching: .videos)
        .onChange(of: selectedVideo) { newValue in
            print("📹 selectedVideo 改变: \(newValue != nil ? "有值" : "nil")")
            print("📹 hasAppeared: \(hasAppeared), isUploadingVideo: \(isUploadingVideo)")
            guard hasAppeared, !isUploadingVideo else {
                print("📹 跳过处理: hasAppeared=\(hasAppeared), isUploadingVideo=\(isUploadingVideo)")
                return
            }
            if newValue != nil {
                print("📹 开始上传视频")
                uploadVideo()
            }
        }
    }
    
    private var showQuickOptions: Bool {
        // 在聊天页面且没有消息时显示，有输入内容时隐藏
        // 注意：即使输入框聚焦，只要没有输入内容，也显示快捷选项
        let shouldShow = showChatView && messages.isEmpty && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return shouldShow
    }
    
    private func requestPermissionAndStart() {
        #if DEBUG
        // 在 Preview 环境中，直接打开相机页面，跳过权限检查
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            isPresentingCamera = true
            return
        }
        #endif
        
        cameraManager.requestAndStart { success, message in
            if success {
                isPresentingCamera = true
            } else {
                permissionMessage = message
                showPermissionAlert = true
            }
        }
    }
    
    private func goBack() {
        isTextFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        messages.removeAll()
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let userInput = inputText.trimmingCharacters(in: .whitespaces)
        let userMessage = Message(content: userInput, isUser: true)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        
        isTextFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        bedrockService.sendMessage(userInput) { result in
            isLoading = false
            switch result {
            case .success(let response):
                let formatted = formatAIOutput(response)
                let aiMessage = Message(content: formatted, isUser: false)
                messages.append(aiMessage)
            case .failure(let error):
                let errorMessage = Message(content: "Error: \(error.localizedDescription)", isUser: false)
                messages.append(errorMessage)
            }
        }
    }
    
    private func uploadVideo() {
        print("🚀 uploadVideo() 被调用")
        guard let videoItem = selectedVideo, !isUploadingVideo else {
            print("🚀 uploadVideo() 提前返回: selectedVideo=\(selectedVideo != nil), isUploadingVideo=\(isUploadingVideo)")
            return
        }
        
        print("🚀 开始处理视频上传")
        isUploadingVideo = true
        isLoading = true
        isTextFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        let userMessage = Message(content: "📹 Uploading video...", isUser: true)
        messages.append(userMessage)
        
        // 在后台线程加载视频数据
        Task {
            print("📥 开始加载视频数据")
            do {
                guard let videoData = try await videoItem.loadTransferable(type: Data.self) else {
                    print("❌ 无法加载视频数据")
                    await MainActor.run {
                        isLoading = false
                        isUploadingVideo = false
                        let errorMessage = Message(content: "Error: Unable to read video", isUser: false)
                        messages.append(errorMessage)
                        selectedVideo = nil
                    }
                    return
                }
                
                print("✅ 视频数据加载成功，大小: \(videoData.count) bytes")
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                try videoData.write(to: tempURL)
                print("✅ 视频已保存到临时文件: \(tempURL.path)")
                
                print("📤 开始调用 uploadAndAnalyzeVideo")
                videoUploadService.uploadAndAnalyzeVideo(videoURL: tempURL) { result in
                    print("📥 uploadAndAnalyzeVideo 回调收到结果")
                    DispatchQueue.main.async {
                        isLoading = false
                        isUploadingVideo = false
                        selectedVideo = nil
                        
                        if let lastIndex = messages.indices.last, messages[lastIndex].content == "📹 Uploading video..." {
                            messages.removeLast()
                        }
                        
                        switch result {
                        case .success(let analysis):
                            print("✅ 视频分析成功")
                            // 添加专业的报告标题并格式化输出
                            let rawReport = "Your professional Squat report is ready!\n\n" + analysis
                            let formatted = formatAIOutput(rawReport)
                            let aiMessage = Message(content: formatted, isUser: false)
                            messages.append(aiMessage)
                        case .failure(let error):
                            print("❌ 视频分析失败: \(error.localizedDescription)")
                            let errorMessage = Message(content: "Error: \(error.localizedDescription)", isUser: false)
                            messages.append(errorMessage)
                        }
                        
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }
            } catch {
                print("❌ 加载视频数据异常: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    isUploadingVideo = false
                    selectedVideo = nil
                    let errorMessage = Message(content: "Error: \(error.localizedDescription)", isUser: false)
                    messages.append(errorMessage)
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            if message.isUser {
                SelectableLabel(text: message.content,
                                font: .systemFont(ofSize: 16),
                                textColor: .white,
                                alignment: .left)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.98, green: 0.45, blue: 0.09))
                    .cornerRadius(20)
                    .multilineTextAlignment(.trailing)
            } else {
                aiMessageView(content: message.content)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
            }
            
            if !message.isUser {
                Spacer()
            }
        }
        .textSelection(.enabled)
    }

    // AI 消息视图，首行加粗放大并使用橙色
    private func aiMessageView(content: String) -> some View {
        let lines = content.components(separatedBy: .newlines)
        let title = lines.first ?? ""
        let body = lines.dropFirst().joined(separator: "\n")
        let scoreValue = parseScore(from: content)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty {
                    SelectableLabel(
                        text: title,
                        font: .systemFont(ofSize: 24, weight: .heavy),
                        textColor: UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1.0),
                        alignment: .left
                    )
                }
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SelectableLabel(
                        text: body,
                        font: .systemFont(ofSize: 16),
                        textColor: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0),
                        alignment: .left
                    )
                }
            }
            if let score = scoreValue {
                ScoreRingView(score: score)
                    .frame(width: 160, height: 160)
                    .padding(.top, 4)
                    .onAppear {
                        UserDefaults.standard.set(score, forKey: "lastNovaScore")
                        NotificationCenter.default.post(name: .init("lastNovaScoreUpdated"), object: nil)
                    }
            }
        }
        .textSelection(.enabled)
    }
    
    // 解析 "SQUAT SCORE: xx/yy" 提取分数百分比
    private func parseScore(from text: String) -> Double? {
        // 寻找形如 "SQUAT SCORE: 52/100"
        guard let range = text.range(of: "SQUAT SCORE:") else { return nil }
        let after = text[range.upperBound...]
        // 获取冒号后的第一个数字/数字
        let tokens = after.split(whereSeparator: { $0.isWhitespace || $0 == "\n" })
        guard let first = tokens.first else { return nil }
        let scoreParts = first.split(separator: "/")
        guard scoreParts.count == 2,
              let gained = Double(scoreParts[0].trimmingCharacters(in: .whitespaces)),
              let total = Double(scoreParts[1].trimmingCharacters(in: .whitespaces)),
              total > 0 else { return nil }
        return (gained / total) * 100.0
    }
}

// 小圆环显示得分
struct ScoreRingView: View {
    let score: Double // 0-100
    
    var body: some View {
        let progress = max(0, min(score / 100.0, 1.0))
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [
                        Color(red: 0.98, green: 0.45, blue: 0.09),
                        Color(red: 0.98, green: 0.7, blue: 0.4),
                        Color(red: 0.98, green: 0.45, blue: 0.09)
                    ]), center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(String(format: "%.0f", score))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.45, blue: 0.09))
                Text("score")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
        }
    }
}

// 快捷选项按钮
struct QuickChip: View {
    let emoji: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct CircleProgressView: View {
    // 最近一次 nova 模型得分（0~100）
    @State private var recentNovaScore: Double = UserDefaults.standard.double(forKey: "lastNovaScore")
    
    var body: some View {
        let clamped = max(0, min(recentNovaScore, 100))
        let progress = clamped / 100.0
        // 显示最近一次 Nova 分数的渐变圆环，带数码风格文字
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.12), lineWidth: 12)
                        .frame(width: 236, height: 236)
            
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.00, green: 0.55, blue: 0.15),
                            Color(red: 0.98, green: 0.45, blue: 0.09),
                            Color(red: 1.00, green: 0.70, blue: 0.30),
                            Color(red: 1.00, green: 0.55, blue: 0.15)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 236, height: 236)
            
            VStack(spacing: 6) {
                Text("Your recent squat score")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.40, green: 0.40, blue: 0.45))
                    .tracking(0.5)
                Text(String(format: "%.0f", clamped))
                    .font(.system(size: 44, weight: .black, design: .monospaced))
                    .foregroundColor(Color(red: 0.98, green: 0.45, blue: 0.09))
                    .shadow(color: Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.35), radius: 4, x: 0, y: 2)
                    .tracking(1.0)
            }
        }
        .onAppear {
            recentNovaScore = UserDefaults.standard.double(forKey: "lastNovaScore")
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("lastNovaScoreUpdated"))) { _ in
            recentNovaScore = UserDefaults.standard.double(forKey: "lastNovaScore")
        }
    }
}

// 可精确选中文本的 UILabel 封装
struct SelectableLabel: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let alignment: NSTextAlignment
    
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textAlignment = alignment
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        uiView.font = font
        uiView.textColor = textColor
        uiView.textAlignment = alignment
    }
}

// 聊天页预览（便于在 CodeX/Xcode 看到聊天界面）
struct ChatPreviewView: View {
    private let sampleMessages: [Message] = [
        Message(content: "Hey, can you analyze my squat?", isUser: true),
        Message(content: "Sure. Please upload your squat video and I will provide detailed analysis.", isUser: false),
        Message(content: "Uploaded! Waiting for feedback.", isUser: true),
        Message(content: """
🏆 SQUAT SCORE: 62/100
Knee Alignment: Incorrect – moderate valgus observed.
Recommendations:
1) Keep knees tracking over toes.
2) Strengthen glutes and VMO.
""", isUser: false)
    ]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sampleMessages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 80)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
    }
}

struct ChatPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        ChatPreviewView()
    }
}

// 使用 @ObservableObject 包装 CameraService，以便在 View 中观察状态
class CameraManager: ObservableObject {
    let cameraService: CameraService
    
    init() {
        print("📷 CameraManager init 开始")
        self.cameraService = CameraService()
        print("📷 CameraManager init 完成")
    }
    
    func requestAndStart(completion: @escaping (Bool, String) -> Void) {
        cameraService.setupAndStartSession { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, "")
                }
            }
        }
    }
    
    func stopCamera() {
        cameraService.stopSession()
    }

    func startRecording(progress: @escaping (Bool, String) -> Void, finished: @escaping (Bool, Error?) -> Void) {
        cameraService.startRecording { error in
            if let error = error {
                progress(false, error.localizedDescription)
            } else {
                progress(true, "")
            }
        } finished: { url, error in
            if let error = error {
                finished(false, error)
            } else {
                finished(true, nil)
            }
        }
    }
    
    func stopRecording() {
        cameraService.stopRecording()
    }
}

// 相机全屏页面，左上角返回
struct CameraScreen: View {
    @ObservedObject var cameraManager: CameraManager
    let onClose: () -> Void
    
    init(cameraManager: CameraManager, onClose: @escaping () -> Void) {
        self._cameraManager = ObservedObject(wrappedValue: cameraManager)
        self.onClose = onClose
    }
    
    @State private var isRecording: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var alertMessage: String = ""
    
    var body: some View {
        ZStack {
            CameraPreview(cameraService: cameraManager.cameraService)
                .ignoresSafeArea()
            
            VStack {
                // 顶部区域：返回按钮和提示
                HStack(spacing: 12) {
                    Button(action: {
                        onClose()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Color.black.opacity(0.4)
                                    .background(.ultraThinMaterial)
                            )
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .padding(.top, 8)
                    
                    Spacer()
                    
                Text("Please ensure the camera is directly in front of your squatting area")
                        .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Color.black.opacity(0.4)
                                .background(.ultraThinMaterial)
                        )
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // 底部录制按钮
                Button(action: {
                    if isRecording {
                        cameraManager.stopRecording()
                    } else {
                        cameraManager.startRecording { success, message in
                            if !success {
                                alertMessage = message
                                showSavedAlert = true
                            }
                        } finished: { ok, err in
                            if let err = err {
                                alertMessage = err.localizedDescription
                            } else {
                                alertMessage = "Video saved to Photos."
                            }
                            showSavedAlert = true
                        }
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isRecording.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                isRecording 
                                    ? Color(red: 0.98, green: 0.45, blue: 0.09)
                                    : Color(red: 0.98, green: 0.45, blue: 0.09)
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.5), radius: 20, x: 0, y: 8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                            )
                        
                        if isRecording {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
        }
        .alert("Notice", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
}

// 确保在 info.plist 中添加 NSCameraUsageDescription 键值对，说明使用摄像头的目的，否则 App 会崩溃。

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
        ContentView()
                .environmentObject(NetworkMonitor())
                .previewDisplayName("Main View")
            
            ContentViewWithCamera()
                .previewDisplayName("With Camera Screen")
        }
    }
}

struct ContentViewWithCamera: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isPresentingCamera = false
    
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.96, blue: 0.97)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("Preview Mode")
                    .font(.title)
                    .foregroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))
                
                Button(action: {
                    isPresentingCamera = true
                }) {
                    Text("Start Squatting Now")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.98, green: 0.45, blue: 0.09))
                        .cornerRadius(9999)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: $isPresentingCamera) {
            CameraScreen(cameraManager: cameraManager) {
                cameraManager.stopCamera()
                DispatchQueue.main.async {
                    isPresentingCamera = false
                }
            }
        }
    }
}
#endif
