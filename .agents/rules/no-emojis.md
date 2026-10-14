---
name: no-emojis
description: Strict prohibition of emojis across all code, scripts, documentation, commit messages, and agent responses. Only clean unicode symbols and text badges are allowed.
trigger: always_on
---

# Strict No-Emoji & Unicode Icons Policy

Moi noi dung trong project nay — bao gom Swift source, shell scripts, markdown docs, commit messages, va phan hoi cua AI agent — **TUYET DOI KHONG DUNG EMOJI HINH ANH (Pictographic / Colored Emojis)**.

---

## 1. Cam (Prohibited)

Khong dung emoji do hoa trong bat ky nguon canh nao. Vi du bi cam:
`🚀`, `🐳`, `⚠️`, `🔒`, `🛑`, `🔥`, `⚡`, `✅`, `❌`, `📦`, `🛠️`, `📝`, `🎉`, `📊`, `🔍`, `📌`

---

## 2. Tieu Chuan Thay The (Allowed)

Chi su dung ky tu Unicode don sac hoac nhan van ban:

### 2.1. Nhan Trang Thai & Muc Do (Text Badges):
* Thanh cong / Hoat dong: `[OK]`, `[UP]`, `[SUCCESS]`
* Loi / Su co: `[ERR]`, `[DOWN]`, `[ERROR]`, `[CRITICAL]`
* Canh bao: `[WARN]`, `[WARNING]`
* Thong tin: `[INFO]`, `[NOTE]`

### 2.2. Ky Tu Phan Cap & Box Drawing:
* `•` (Bullet point)
* `─`, `│`, `┌`, `┐`, `└`, `┘`, `├`, `┤`, `┬`, `┴`, `┼`

### 2.3. Mui Ten & Hinh Hoc:
* `→`, `←`, `↑`, `↓`
* `▲`, `▼`, `►`, `◄`
* `✓`, `✗`
* `■`, `□`, `●`, `○`
