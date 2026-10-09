import Foundation
import UIKit
import SwiftUI

/// 应用更新管理器：检查新版本、下载IPA、显示进度、分享安装
final class AppUpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    /// 单例
    static let shared = AppUpdateManager()

    /// GitHub 仓库地址
    private let repoOwner = "lambret-1"
    private let repoName = "ComfyUIDemo"

    /// 当前状态
    @Published var isChecking: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?
    @Published var latestVersion: String?
    @Published var hasUpdate: Bool = false

    /// 下载完成回调
    private var downloadCompletion: ((URL?) -> Void)?
    /// 下载任务
    private var downloadTask: URLSessionDownloadTask?
    /// 下载会话
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
    }

    // MARK: - 检查更新

    /// 检查是否有新版本
    func checkForUpdate(currentVersion: String, completion: @escaping (Bool, String?) -> Void) {
        isChecking = true
        downloadError = nil

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            completion(false, nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                guard let data = data, error == nil else {
                    completion(false, nil)
                    return
                }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {
                        let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                        self?.latestVersion = latestVersion
                        let hasUpdate = self?.isVersionNewer(latest: latestVersion, current: currentVersion) ?? false
                        self?.hasUpdate = hasUpdate
                        completion(hasUpdate, latestVersion)
                    } else {
                        completion(false, nil)
                    }
                } catch {
                    completion(false, nil)
                }
            }
        }.resume()
    }

    /// 版本号比较：latest > current 返回 true
    private func isVersionNewer(latest: String, current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(latestParts.count, currentParts.count) {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    // MARK: - 下载更新

    /// 下载最新版本 IPA
    func downloadLatestIPA(completion: @escaping (URL?) -> Void) {
        guard let version = latestVersion else {
            completion(nil)
            return
        }
        downloadCompletion = completion
        downloadProgress = 0
        isDownloading = true
        downloadError = nil

        // 从 GitHub Release 资产下载 IPA
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/tags/v\(version)"
        guard let url = URL(string: urlString) else {
            isDownloading = false
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.downloadError = "获取下载地址失败"
                    completion(nil)
                }
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let assets = json["assets"] as? [[String: Any]],
                   let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
                   let downloadURLString = asset["browser_download_url"] as? String,
                   let downloadURL = URL(string: downloadURLString) {
                    DispatchQueue.main.async {
                        self?.startDownload(url: downloadURL)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.isDownloading = false
                        self?.downloadError = "未找到 IPA 安装包"
                        completion(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.downloadError = "解析下载地址失败"
                    completion(nil)
                }
            }
        }.resume()
    }

    private func startDownload(url: URL) {
        let task = session.downloadTask(with: url)
        downloadTask = task
        task.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 移动到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "ComfyUIDemo-\(latestVersion ?? "update").ipa"
        let destinationURL = tempDir.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadProgress = 1.0
                self.downloadCompletion?(destinationURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadError = "保存文件失败：\(error.localizedDescription)"
                self.downloadCompletion?(nil)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        DispatchQueue.main.async {
            self.downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadError = "下载失败：\(error.localizedDescription)"
                self.downloadCompletion?(nil)
            }
        }
    }

    // MARK: - 分享安装包

    /// 弹出 iOS 原生分享弹窗，用于 TrollStore 安装 IPA
    func shareIPA(_ fileURL: URL, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = viewController.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: viewController.view.bounds.midX,
            y: viewController.view.bounds.midY,
            width: 0,
            height: 0
        )
        viewController.present(activityVC, animated: true)
    }
}
