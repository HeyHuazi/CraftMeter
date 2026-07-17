/**
 * [INPUT]: 依赖 macOS NSPasteboard、NewRelaySiteDraftState 与 SettingsProviderConfigurationFacade
 * [OUTPUT]: 对外提供 NewAPI「粘贴 cURL 并导入」视图块及一次性剪贴板动作
 * [POS]: Settings 的 cURL 高级导入交互边界；原始命令只在按钮任务调用栈中存在，不写入 SwiftUI 状态
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import AppKit
import Foundation
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var relayCurlImportSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                settingsSmallOutlineButton(
                    newRelaySiteDraft.curlImportInFlight
                        ? viewModel.localizedText("正在验证", "Verifying")
                        : viewModel.localizedText("粘贴 cURL 并导入", "Paste cURL & Import"),
                    width: 112
                ) {
                    importNewAPISiteFromPasteboard()
                }
                .disabled(newRelaySiteDraft.curlImportInFlight)

                if newRelaySiteDraft.curlImportInFlight {
                    ProgressView()
                        .controlSize(.small)
                } else if let result = newRelaySiteDraft.curlImportResult {
                    Text(result.message)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(result.success ? Color(hex: 0x69BD64) : Color(hex: 0xEB654F))
                }
            }

            thirdPartyHintText(
                viewModel.localizedText(
                    "在已登录的 NewAPI 页面复制 /api/user/self 请求为 cURL；CraftMeter 会自动识别站点、User ID 与认证，并仅在验证成功后保存。",
                    "Copy the /api/user/self request as cURL from a signed-in NewAPI page. CraftMeter detects the site, user ID, and authentication, then saves only after validation."
                )
            )
        }
        .padding(.leading, thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing - 3)
    }

    func importNewAPISiteFromPasteboard() {
        guard !newRelaySiteDraft.curlImportInFlight else { return }
        guard let command = NSPasteboard.general.string(forType: .string),
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            newRelaySiteDraft.curlImportResult = RelayCurlImportDisplayResult(
                success: false,
                host: nil,
                credentialKind: nil,
                message: viewModel.localizedText("剪贴板为空", "Clipboard is empty"),
                providerID: nil
            )
            return
        }

        newRelaySiteDraft.curlImportInFlight = true
        newRelaySiteDraft.curlImportResult = nil
        Task {
            let result = await providerConfigurationFacade.importNewAPISiteFromCurl(command)
            newRelaySiteDraft.curlImportInFlight = false
            newRelaySiteDraft.curlImportResult = result
            guard result.success, let providerID = result.providerID else { return }

            navigationState.selectedGroup = .thirdParty
            navigationState.selectedProviderID = providerID
            showingRelayNewSiteDraft = false
            let templateID = newRelaySiteDraft.templateID
            newRelaySiteDraft.reset(using: templateID)
            applyNewRelayTemplate(templateID)
            cancelActiveRelayTitleEdit()
        }
    }
}
