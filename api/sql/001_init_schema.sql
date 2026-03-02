CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(32) UNIQUE,
  email VARCHAR(128) UNIQUE,
  nickname VARCHAR(64),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS couples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id UUID NOT NULL REFERENCES users(id),
  user_b_id UUID NOT NULL REFERENCES users(id),
  status VARCHAR(16) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'closed')),
  paired_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (user_a_id <> user_b_id),
  UNIQUE (user_a_id, user_b_id)
);

CREATE INDEX IF NOT EXISTS idx_couples_status ON couples(status);

CREATE TABLE IF NOT EXISTS daily_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  author_user_id UUID NOT NULL REFERENCES users(id),
  event_type VARCHAR(24) NOT NULL DEFAULT 'other'
    CHECK (event_type IN ('date', 'gift', 'interaction', 'other')),
  mood_score SMALLINT NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
  content TEXT NOT NULL,
  event_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS daily_entry_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id UUID NOT NULL REFERENCES daily_entries(id) ON DELETE CASCADE,
  tag VARCHAR(64) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (entry_id, tag)
);

CREATE TABLE IF NOT EXISTS daily_media (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id UUID NOT NULL REFERENCES daily_entries(id) ON DELETE CASCADE,
  media_type VARCHAR(16) NOT NULL
    CHECK (media_type IN ('image', 'video')),
  url TEXT NOT NULL,
  cover_url TEXT,
  duration_sec INT,
  width INT,
  height INT,
  size_bytes BIGINT,
  sort_order INT NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_media_duration
    CHECK (
      (media_type = 'image' AND (duration_sec IS NULL OR duration_sec = 0))
      OR
      (media_type = 'video' AND (duration_sec IS NULL OR duration_sec >= 0))
    )
);

CREATE INDEX IF NOT EXISTS idx_daily_entries_couple_time
  ON daily_entries (couple_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_daily_entries_author_time
  ON daily_entries (author_user_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_daily_tags_entry
  ON daily_entry_tags (entry_id);
CREATE INDEX IF NOT EXISTS idx_daily_media_entry_sort
  ON daily_media (entry_id, sort_order);

CREATE TABLE IF NOT EXISTS conflict_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  trigger_type VARCHAR(32) NOT NULL DEFAULT 'other'
    CHECK (trigger_type IN ('communication', 'money', 'housework', 'boundary', 'family', 'other')),
  status VARCHAR(24) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'mediating', 'resolved', 'archived')),
  risk_level VARCHAR(16) NOT NULL DEFAULT 'low'
    CHECK (risk_level IN ('low', 'medium', 'high')),
  opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conflict_inputs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES conflict_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  facts TEXT NOT NULL,
  feelings TEXT NOT NULL,
  needs TEXT NOT NULL,
  expectation TEXT,
  emotion_score SMALLINT NOT NULL CHECK (emotion_score BETWEEN 1 AND 10),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, user_id)
);

CREATE TABLE IF NOT EXISTS conflict_mediations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES conflict_sessions(id) ON DELETE CASCADE,
  version INT NOT NULL DEFAULT 1,
  consensus_facts JSONB NOT NULL DEFAULT '[]'::jsonb,
  differences JSONB NOT NULL DEFAULT '[]'::jsonb,
  needs_translation JSONB NOT NULL DEFAULT '[]'::jsonb,
  tonight_action TEXT,
  repair_plan_72h JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, version)
);

CREATE INDEX IF NOT EXISTS idx_conflict_sessions_couple_time
  ON conflict_sessions (couple_id, opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_conflict_sessions_status
  ON conflict_sessions (status);
CREATE INDEX IF NOT EXISTS idx_conflict_inputs_session
  ON conflict_inputs (session_id);
CREATE INDEX IF NOT EXISTS idx_conflict_mediations_session
  ON conflict_mediations (session_id, version DESC);

CREATE TABLE IF NOT EXISTS repair_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES conflict_sessions(id) ON DELETE SET NULL,
  couple_id UUID NOT NULL REFERENCES couples(id),
  title VARCHAR(256) NOT NULL,
  detail TEXT,
  assignee_user_id UUID REFERENCES users(id),
  due_at TIMESTAMPTZ,
  status VARCHAR(24) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'done', 'expired', 'canceled')),
  completed_by UUID REFERENCES users(id),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS repair_task_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES repair_tasks(id) ON DELETE CASCADE,
  action_type VARCHAR(32) NOT NULL
    CHECK (action_type IN ('created', 'status_changed', 'comment', 'reminder_sent')),
  actor_user_id UUID REFERENCES users(id),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_repair_tasks_couple_status_due
  ON repair_tasks (couple_id, status, due_at);
CREATE INDEX IF NOT EXISTS idx_repair_tasks_session
  ON repair_tasks (session_id);
CREATE INDEX IF NOT EXISTS idx_repair_task_logs_task_time
  ON repair_task_logs (task_id, created_at DESC);

CREATE TABLE IF NOT EXISTS weekly_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  week_start_date DATE NOT NULL,
  positive_interactions_count INT NOT NULL DEFAULT 0,
  conflict_count INT NOT NULL DEFAULT 0,
  repair_completion_rate NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (repair_completion_rate BETWEEN 0 AND 100),
  emotion_volatility NUMERIC(6,3) NOT NULL DEFAULT 0,
  summary TEXT,
  suggestion TEXT,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (couple_id, week_start_date)
);

CREATE INDEX IF NOT EXISTS idx_weekly_reports_couple_week
  ON weekly_reports (couple_id, week_start_date DESC);

CREATE TABLE IF NOT EXISTS memory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  user_id UUID REFERENCES users(id),
  source_type VARCHAR(32) NOT NULL
    CHECK (source_type IN ('daily', 'conflict_input', 'mediation', 'repair_task', 'weekly')),
  source_id UUID NOT NULL,
  scene_session_id UUID,
  tags TEXT[] NOT NULL DEFAULT '{}',
  emotion_score SMALLINT,
  text_body TEXT NOT NULL,
  happened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  memos_status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (memos_status IN ('pending', 'synced', 'failed')),
  memos_ref_id VARCHAR(128),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (source_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_memory_items_couple_type_time
  ON memory_items (couple_id, source_type, happened_at DESC);
CREATE INDEX IF NOT EXISTS idx_memory_items_session
  ON memory_items (scene_session_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_status
  ON memory_items (memos_status);
CREATE INDEX IF NOT EXISTS idx_memory_items_tags_gin
  ON memory_items USING GIN (tags);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_couples_updated_at ON couples;
CREATE TRIGGER trg_couples_updated_at
BEFORE UPDATE ON couples
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_daily_entries_updated_at ON daily_entries;
CREATE TRIGGER trg_daily_entries_updated_at
BEFORE UPDATE ON daily_entries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_conflict_sessions_updated_at ON conflict_sessions;
CREATE TRIGGER trg_conflict_sessions_updated_at
BEFORE UPDATE ON conflict_sessions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_conflict_inputs_updated_at ON conflict_inputs;
CREATE TRIGGER trg_conflict_inputs_updated_at
BEFORE UPDATE ON conflict_inputs
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_repair_tasks_updated_at ON repair_tasks;
CREATE TRIGGER trg_repair_tasks_updated_at
BEFORE UPDATE ON repair_tasks
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
