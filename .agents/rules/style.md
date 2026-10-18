---
name: style
description: Ngôn ngữ và ký tự cho repo MeMo. Gộp english-only và no-emojis.
trigger: always_on
---

# Style: ngôn ngữ và ký tự

## Tiếng Anh bắt buộc
Mã nguồn Swift (code + comment), shell script, workflow `.github/`, commit message, và markdown ở thư mục gốc (README, AGENTS, CLAUDE, GEMINI).

Commit theo Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `style:`, `chore:`.

## Tiếng Việt được phép
Toàn bộ thư mục `.agents/` (rules, skills, memory) và phần trả lời cho chủ repo.

## Emoji
Cấm emoji dạng hình ảnh/màu ở mọi nơi (code, script, docs, commit, câu trả lời của agent). Cụ thể là các khối Unicode U+1F000-U+1FAFF, U+2600-U+27BF (trừ dấu tick/cross bên dưới), U+2B50-U+2B55, U+FE0F, U+200D.

Dùng nhãn văn bản: `[OK]`, `[WARN]`, `[ERR]`, `[INFO]`, `[UP]`, `[DOWN]`.

## Ký tự Unicode được phép
Không phải emoji, được dùng bình thường, kể cả trong Swift và script: bullet, box drawing, mũi tên, hình học đơn sắc, dấu tick/cross đơn sắc, `°`, dấu ba chấm, gạch dài.

## Kiểm tra tự động
`scripts/policy-check.sh` quét emoji trên mọi file `.swift .sh .md .yml .plist .py` (pre-commit và CI). Quy tắc này do script thực thi, không phụ thuộc vào việc agent nhớ.
