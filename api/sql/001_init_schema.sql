-- Couple Relationship Copilot MVP schema

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(32) UNIQUE,
  nickname VARCHAR(64),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS couples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id UUID NOT NULL REFERENCES users(id),
  user_b_id UUID NOT NULL REFERENCES users(id),
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_a_id, user_b_id)
);

CREATE TABLE IF NOT EXISTS daily_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  author_user_id UUID NOT NULL REFERENCES users(id),
  event_type VARCHAR(24) NOT NULL,
  mood_score SMALLINT NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
  feedback_tags TEXT[] DEFAULT '{}',
  content TEXT NOT NULL,
  media_url TEXT,
  event_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conflict_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  status VARCHAR(24) NOT NULL DEFAULT 'open',
  risk_flag BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ
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
  UNIQUE (session_id, user_id)
);

CREATE TABLE IF NOT EXISTS repair_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES conflict_sessions(id) ON DELETE CASCADE,
  couple_id UUID NOT NULL REFERENCES couples(id),
  title VARCHAR(256) NOT NULL,
  due_at TIMESTAMPTZ,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  completed_by UUID REFERENCES users(id),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS weekly_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_id UUID NOT NULL REFERENCES couples(id),
  week_start DATE NOT NULL,
  positive_interactions INT NOT NULL DEFAULT 0,
  conflict_count INT NOT NULL DEFAULT 0,
  repair_completion_rate NUMERIC(5,2) NOT NULL DEFAULT 0,
  emotion_volatility NUMERIC(5,2) NOT NULL DEFAULT 0,
  summary TEXT,
  suggestion TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (couple_id, week_start)
);

CREATE INDEX IF NOT EXISTS idx_daily_entries_couple_time
  ON daily_entries (couple_id, event_time DESC);

CREATE INDEX IF NOT EXISTS idx_conflict_sessions_couple_created
  ON conflict_sessions (couple_id, created_at DESC);
