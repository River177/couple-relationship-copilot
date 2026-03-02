# Couple Relationship Copilot

Mobile-first AI product for couples:
- Daily relationship journaling
- Conflict mediation workflow
- 72-hour repair plan tracking
- Weekly relationship health check

## Tech Stack (MVP)
- Mobile: Flutter
- Backend: FastAPI
- DB: PostgreSQL
- Memory: MemOS
- Storage: S3-compatible

## Monorepo Structure
- `app/` Flutter client
- `api/` FastAPI backend
  - `api/sql/` DB schema source of truth
- `docs/` PRD / flows / API specs
- `infra/` deployment and environment templates (e.g. MinIO compose)

## 项目状态（2026-03-02）

### 已完成
- Flutter / PostgreSQL / MinIO 环境可用
- 核心表结构已落地，`api/sql/` 为 schema 单一事实来源
- API 已支持：`/health`、`/daily`、`/conflict`、`/media`（`/weekly/report` 当前占位）
- MemOS 已接入 `daily` 与 `conflict` 的写入链路（含本地 `memory_items` 状态追踪）
- 前端已完成：首页、日常记录页、冲突调解页（可用版 UI）

### 进行中 / 待完成
- 周报接口真实聚合（替换占位逻辑）
- 每周体检页可用版 UI 与联调
- 媒体链路增强（元数据、清理策略、上传校验）
- 测试与工程化补齐（单测/集成测试、分层重构）

### 详细说明
- 详见：`docs/项目进展与后续计划-2026-03-02.md`

## Next Steps
1. Implement real aggregation for `GET /weekly/report`
2. Build weekly-check UI page and connect backend
3. Add MemOS retrieval in conflict + weekly flows
4. Add tests (API + integration)
