# Inbox

把 Notion 导出的 Markdown 或 zip 放到这里，然后用脚本导入到仓库。

推荐流程：

1. 在 Notion 里选择 `Export`
2. 格式选择 `Markdown & CSV`
3. 把导出的 `.zip` 放到 `inbox/`
3. 在仓库根目录运行：

直接双击仓库根目录的：

```text
Import Notion Export.bat
```

它会自动选择 `inbox/` 中最新的 `.zip` 文件导入。

或手动指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-notion.ps1 -Source .\inbox\notion-export.zip -Category notes -Tags "Photoshop, DEM, 等高线"
```

脚本会自动：

- 读取 Notion 导出的 Markdown 标题
- 创建 `notes/YYYY/YYYY-MM-DD-topic-slug/`
- 把正文保存为 `README.md`
- 把图片整理到 `assets/`
- 压缩/缩放过大的图片
- 修正 Markdown 图片路径
- 更新 `notes/README.md` 和年份索引
- 可选自动 commit / push

如果不想自动上传，加 `-NoPush`，确认结果无误后再用 GitHub Desktop 提交。
