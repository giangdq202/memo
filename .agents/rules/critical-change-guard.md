---
name: critical-change-guard
description: Thay đổi nào phải dừng lại hỏi chủ repo, kèm guardrail về filesystem và build artifact. Gộp production-safety.
trigger: always_on
---

# Critical Change Guard

Trước khi làm bất kỳ việc nào dưới đây, agent phải dừng, nêu rủi ro, chờ xác nhận.

## [CRITICAL]
1. Sửa `SMC.swift`: IOKit mức thấp, sai một byte có thể crash hoặc kernel panic. Pre-commit chặn trừ khi `ALLOW_SMC=1`.
2. Sửa `Info.plist`, đặc biệt `LSUIElement` (icon Dock) và `CFBundleIdentifier` (domain UserDefaults, login item).
3. Đổi cấu trúc `.app` bundle (`Contents/MacOS`, `Contents/Resources`).
4. Thay AppKit bằng SwiftUI, thêm dependency, thêm `.xcodeproj`.

## [WARN]
5. Hạ deployment target dưới macOS 11.0.
6. Đổi SDK path hoặc compiler flag trong `build.sh` (`-Osize`, `-wmo`, `-dead_strip`).
7. Đổi tên hoặc xóa UserDefaults key (mất setting của bản đã cài).

## [INFO] Nhắc trước khi làm
8. Ghi ngoài thư mục project: `~/Library`, `/Applications`, `/tmp`.
9. Chạy `install.sh` hoặc `uninstall.sh` (tác động máy thật).
10. `rm -rf` trong project, ngoại trừ việc `build.sh` đã làm với `MeMo.app`.

## Không bao giờ commit
`MeMo.app`, `MeMo_bin`, `*_arm64`, `*_x86_64`, `Version.swift`, `.agents/memory/build_history.log`, mật khẩu/token/key. `policy-check.sh` kiểm tra các file này.

## Mẫu xác nhận
```
[CRITICAL CHANGE]
Action : <việc định làm>
Target : <file / đường dẫn>
Why    : <lý do cần>
Risk   : <rủi ro nếu sai>
Proceed?
```
