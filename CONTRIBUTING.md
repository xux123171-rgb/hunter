# 贡献指南（CONTRIBUTING）

## 什么值得提

* 新腿（工具封装）：任何"腿"必须遵守 SOP 铁律——零落地探活、payload 克制、非破坏。做不到合规的 PR 不会被收。
* 判死案例回写：`sop/PLAYBOOK.md` 的判死速查表欢迎补充（附证据结构，不附具体目标敏感数据）。
* 词表 / nuclei 模板的合规子集。
* Bug 修复与跨平台适配（macOS / Linux 路径、Shell 差异）。

## 硬性规矩

1. **离线回归必须绿**：改完跑 `bash tools/test.sh`（30 秒、零真实请求），任何 FAIL 不合入。
2. **不提交目标数据**：`scratch/`、`journal/`、`reports/` 已被 .gitignore 挡掉，PR 前自查 `git status`。
3. **不提交引擎二进制**：`bin/*.exe` 走 gitignore，由 `tools/install-toolchain.sh` 重建。
4. 新工具进 `tools/`（可执行 shell/python）+ 在 `mcp/server.py` 注册成腿 + 在 `mcp/full_test.py` 补断言。
5. 合规红线：PR 里不要写"绕过实名/破解验证码/拖库"类能力，此类需求一律拒绝。

## 开发环境

见 `SETUP.md`。核心：Git for Windows（或 bash）+ uv/python 建 `mcp/.venv`，
`bash tools/install-hermes.sh` 一条命令补齐 venv/skill/MCP 注册。

## 提交格式

commit 标题 `<type>(<腿>): <做了什么>`，如 `fix(mcp): BASH 发现拒 WSL 桩`。
一次改动一个主题；行为变更需在 `sop/` 或 README 同步说明。
