# 第三方工具 vendor 说明（bin/ 里的二进制不是我们写的）

> 我们的项目 = 脑子（sop/、references/、templates/、tools/*.sh、.git）+ 编排。
> bin/ 里五个二进制是**第三方开源**，我们是使用者，来源与版本如下。
> 二进制本身不入库（.gitignore 挡掉），靠 `tools/install-toolchain.sh` 重建。

| 二进制 | 上游项目 | 版本 | 构建方式 |
|---|---|---|---|
| `ffuf.exe` | github.com/ffuf/ffuf | - | `go install github.com/ffuf/ffuf/v2@latest` |
| `katana.exe` | github.com/projectdiscovery/katana | v1.7.0 | `go install github.com/projectdiscovery/katana/cmd/katana@latest` |
| `nuclei.exe` | github.com/projectdiscovery/nuclei | v3.11.1 | `go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest` |
| `httpx.exe` | github.com/projectdiscovery/httpx（**指纹器**，非 Python 包） | v1.12.0 | `go install github.com/projectdiscovery/httpx/cmd/httpx@latest` |
| `cybermes-mcp.exe` | github.com/Zyrexnn/Cybermes（MCP 服务器本体） | v3.4.2 | 从上游 release/构建取二进制 |

## 许可
- ffuf / katana / nuclei / httpx：以各自仓库 LICENSE 为准（ProjectDiscovery 多为 MIT/Apache 双许可）。
- cybermes-mcp：以 Zyrexnn/Cybermes 仓库 LICENSE 为准，**用前核对一次**。
- 若作为开源项目发布，建议在上游 license 允许范围内附带这些说明；闭源/内部使用则保留本文件即可。

## 我们的自研（可整份带走）
`hunter` 方法论 + SOP + 影响/合规门 + 脚本 + 模板 + 编排（本仓库 git 里的 11 个文件）= 100% 我们写的，不依赖任何第三方代码即可读懂方法论。
