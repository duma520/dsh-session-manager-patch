# dsh-session-manager 全选上限热修补丁

把 [dsh-session-manager](https://github.com/hkkz9522/dsh-session-manager) 0.7.8 的「批量操作最多 200 项」放开为**不设上限**。

## 为什么不能只删 200

只删守卫会立刻撞上三处更硬的限制：

| 位置 | 原始限制 | 全选 1888 条的后果 |
|---|---|---|
| `lib/index.js:462` `readBody` | `size > 64 * 1024` 抛 `body-too-large` | 1888 个 36 字符 id 拼 JSON = 88784 字节 → 413 |
| `lib/index.js:2762` `GET /delete-preview` | 查询串 `?sessionIds=` 逗号拼接 | ≈70 KB URL，超 HTTP 请求行上限 |
| `lib/client.js:1456` `runBatch` | 一次性 `await response.json()`，非流式 | 进度条 0 → 100 直接跳，长时间无反馈 |

## 改了什么（共 8 处）

### lib/client.js
1. `:385` 中文文案 `bulk.error.tooMany` → 「批量操作条目较多，将自动分批执行，请耐心等待」
2. `:597` 英文文案 →「Large batch: actions run in chunks and may take a while.」
3. `:1456` `runBatch` 改为**客户端分片**：新增 `BULK_CHUNK_SIZE = 50`，每 50 条串行 POST 一次，每片返回后回调 `onProgress({done, total})`，最后汇总 `summary`
4. `:4790` `selectAllFiltered` 去掉 `rows.length > 200` 守卫
5. `:4804` `executeBulk` 去掉 `ids.length > 200` 守卫
6. `:4868` `runBulk` 去掉 `ids.length > 200` 守卫
7. `:4931` 删除预览从 GET 查询串改为 `POST /delete-preview`（JSON body 传全部 id）

### lib/index.js
8. `:462` `readBody` 上限 64 KiB → 1 MiB
9. `:2689` `POST /batch` 去掉 200 条守卫（保留空数组校验）
10. `:2761` 新增 `POST /delete-preview` 分支，GET 分支保留向后兼容

### lib/annotation-store.js
11. `:149` `batchUpdate` 上限 200 → 10000（当前调用方只传单条，属预防性放开）

## 分片后的体积实测

```
50 条分片请求体：1998 字节
1888 条单次请求体：88784 字节（超过原 64 KiB 限制）
```

## 重打（插件升级后必做）

```powershell
cd G:\Python_Code\dsh-session-manager-patch
powershell -ExecutionPolicy Bypass -File .\apply-patch.ps1
```

脚本会：断硬链接（先复制临时文件、删原文件、再改名）→ 覆盖三个 lib 文件 → `node --check` 语法校验。

## 目录

```
dsh-session-manager-patch/
├── apply-patch.ps1          重打脚本（断链 + 覆盖 + 语法校验）
├── patched/lib/             改好的三个文件
│   ├── client.js
│   ├── index.js
│   └── annotation-store.js
└── version/20261117-v1/lib/ 改动前的原始备份（可回滚）
```

## 回滚

```powershell
$t = "C:\Users\duma520\.dsh\profiles\desktop\node_modules\dsh-session-manager\lib"
$b = "G:\Python_Code\dsh-session-manager-patch\version\20261117-v1\lib"
foreach ($f in "client.js","index.js","annotation-store.js") {
  Copy-Item "$b\$f" "$t\$f.bak" -Force
  Remove-Item "$t\$f" -Force
  Move-Item "$t\$f.bak" "$t\$f" -Force
}
```

## 生效方式

客户端插件无构建步骤，直接由 DSH 加载 `lib/client.js`（见文件头注释与 `package.json` 的 `dsh.client` 声明）。改完在界面按 **F5 刷新**即可生效。

## 已知边界

- 分片之间是**串行**的，1888 条约 38 片。归档走 DSH 官方命令逐条执行，耗时不亚于原来，但进度条现在能真实推进。
- `archive`/`unarchive` 在前端已走 `runArchiveCommand` 逐条分支（`client.js:4816`），不经过 `/batch`；分片只作用于其余动作（delete/move/标注类）。
- 升级到 0.7.9+ 后重打前需先比对上游是否已自行放开限制。
