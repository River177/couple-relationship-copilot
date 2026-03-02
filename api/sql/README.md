# SQL Schema Source of Truth

This folder is the **single source of truth** for database schema SQL files.

- Primary schema file: `001_init_schema.sql`
- Keep SQL migrations / bootstrap scripts here.
- Avoid duplicating schema SQL under `infra/`.

## Why

To avoid drift between multiple copies of schema files and keep backend + DB changes consistent.
