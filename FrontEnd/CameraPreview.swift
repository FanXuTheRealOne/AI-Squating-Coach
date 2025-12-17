//
//  CameraPreview.swift
//  camera
//
//  Created by xufan on 2025/10/6.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewControllerRepresentable {
    
    // 引用你的 CameraService 实例
    let cameraService: CameraService

    // 这是一个特殊的 UIKit 容器，用于托管 AVCaptureVideoPreviewLayer
    class PreviewViewController: UIViewController {
        var cameraService: CameraService
        
        init(cameraService: CameraService) {
            self.cameraService = cameraService
            super.init(nibName: nil, bundle: nil)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // 视图加载后，配置预览层
        override func viewDidLoad() {
            super.viewDidLoad()
            
            // 将预览层添加到视图的 layer 上
            if cameraService.previewLayer.superlayer == nil {
                view.layer.addSublayer(cameraService.previewLayer)
            }
        }
        
        // 视图布局变化时，调整预览层的大小
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            
            // viewDidLayoutSubviews 已经在主线程，直接更新
            cameraService.previewLayer.frame = view.bounds
        }
    }

    // 必须实现的方法 1: 创建 UIKit 视图控制器
    func makeUIViewController(context: Context) -> PreviewViewController {
        let viewController = PreviewViewController(cameraService: cameraService)
        return viewController
    }

    // 必须实现的方法 2: 更新 UIKit 视图控制器 (本例中无需更新)
    func updateUIViewController(_ uiViewController: PreviewViewController, context: Context) {
        //
    }
}
