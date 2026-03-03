-- 002_auth_and_binding_refactor.sql
-- Goal: login session + invitation binding model (no front-end ID input)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------
-- users hardening
-- -------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS avatar_url TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_users_status'
      AND conrelid = 'users'::regclass
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_status CHECK (status IN ('active', 'disabled'));
  END IF;
END $$;

-- -------------------------
-- auth sessions
-- -------------------------
CREATE TABLE IF NOT EXISTS auth_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  refresh_token_hash TEXT NOT NULL,
  device_info JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip INET,
  user_agent TEXT NOT NULL DEFAULT '',
  expired_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expired_at ON auth_sessions(expired_at);

-- -------------------------
-- verification codes
-- -------------------------
CREATE TABLE IF NOT EXISTS auth_verification_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account VARCHAR(255) NOT NULL,
  code_hash TEXT NOT NULL,
  purpose VARCHAR(20) NOT NULL DEFAULT 'login',
  expired_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_auth_code_purpose'
      AND conrelid = 'auth_verification_codes'::regclass
  ) THEN
    ALTER TABLE auth_verification_codes
      ADD CONSTRAINT chk_auth_code_purpose CHECK (purpose IN ('login'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_auth_codes_account ON auth_verification_codes(account, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_codes_expired_at ON auth_verification_codes(expired_at);

-- -------------------------
-- couple invitation model
-- -------------------------
CREATE TABLE IF NOT EXISTS relationship_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_user_id UUID NOT NULL REFERENCES users(id),
  invite_code VARCHAR(16) NOT NULL UNIQUE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  expired_at TIMESTAMPTZ NOT NULL,
  accepted_by_user_id UUID REFERENCES users(id),
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (inviter_user_id IS DISTINCT FROM accepted_by_user_id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_relationship_invites_status'
      AND conrelid = 'relationship_invites'::regclass
  ) THEN
    ALTER TABLE relationship_invites
      ADD CONSTRAINT chk_relationship_invites_status
      CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_invites_inviter ON relationship_invites(inviter_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invites_status ON relationship_invites(status);
CREATE INDEX IF NOT EXISTS idx_invites_expired_at ON relationship_invites(expired_at);

-- -------------------------
-- couples constraints refresh
-- -------------------------
-- normalize legacy status values to new MVP model
UPDATE couples SET status = 'active' WHERE status IN ('paused', 'closed');

ALTER TABLE couples
  DROP CONSTRAINT IF EXISTS couples_status_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_couples_status'
      AND conrelid = 'couples'::regclass
  ) THEN
    ALTER TABLE couples
      ADD CONSTRAINT chk_couples_status CHECK (status IN ('active', 'unbound'));
  END IF;
END $$;

ALTER TABLE couples
  ADD COLUMN IF NOT EXISTS bound_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS unbound_at TIMESTAMPTZ;

-- backfill from old column paired_at if present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'couples' AND column_name = 'paired_at'
  ) THEN
    EXECUTE 'UPDATE couples SET bound_at = paired_at WHERE bound_at IS NULL';
  END IF;
END $$;

-- keep old unique(user_a_id,user_b_id) but add stronger uniqueness for active relationship
CREATE UNIQUE INDEX IF NOT EXISTS uq_couples_pair_active
ON couples ((LEAST(user_a_id::text, user_b_id::text)), (GREATEST(user_a_id::text, user_b_id::text)))
WHERE status = 'active';

CREATE UNIQUE INDEX IF NOT EXISTS uq_couples_user_a_active
ON couples(user_a_id) WHERE status = 'active';

CREATE UNIQUE INDEX IF NOT EXISTS uq_couples_user_b_active
ON couples(user_b_id) WHERE status = 'active';

-- -------------------------
-- triggers for updated_at
-- -------------------------
DO $$
BEGIN
  IF to_regproc('set_updated_at') IS NULL THEN
    CREATE OR REPLACE FUNCTION set_updated_at()
    RETURNS TRIGGER AS $f$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $f$ LANGUAGE plpgsql;
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_relationship_invites_updated_at ON relationship_invites;
CREATE TRIGGER trg_relationship_invites_updated_at
BEFORE UPDATE ON relationship_invites
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- keep couples/users triggers in case DB initialized without 001
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_couples_updated_at ON couples;
CREATE TRIGGER trg_couples_updated_at
BEFORE UPDATE ON couples
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
