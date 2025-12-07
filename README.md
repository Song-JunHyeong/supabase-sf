# Supabase-SF(Self-Hosted)

Production-ready Docker Compose setup for self-hosting Supabase with automated secret management.

> [!CAUTION]
> **For self-hosted deployments only.**
> Using [Supabase Cloud](https://supabase.com/dashboard)? See the [official docs](https://supabase.com/docs).

---

## Quick Start

```bash
# Clone and start
git clone https://github.com/your-org/supabase-sf.git
cd supabase-sf
docker compose up -d   # Auto-generates secrets on first run
```

**Access:**

- **Dashboard**: http://localhost:8000
- **API**: http://localhost:8000/rest/v1/
- **MCP Connection Guide**: `docker logs supabase-mcp-guide`

**Default credentials** (check `.env` after first run):

- Username: `supabase`
- Password: Auto-generated (see `DASHBOARD_PASSWORD` in `.env`)

---

## VPS Panel Deployment (Easypanel, Coolify, etc.)

When deploying via Docker Compose on VPS panels, configure domain routing:

| Setting                   | Value    |
| ------------------------- | -------- |
| **Protocol**        | HTTP     |
| **Port**            | 8000     |
| **Compose Service** | `kong` |

> [!TIP]
> **Quick access via container console (EasyPanel, Coolify, Portainer):**
>
> | Container | Command | Shows |
> |-----------|---------|-------|
> | `mcp-guide` | `mcp` | MCP config for Claude Desktop / Cursor |
> | `env-info` | `show-env` | Environment variables, API keys, login |
>
> **Or via SSH on host:**
>
> ```bash
> ./scripts/show-env.sh   # Environment variables
> ./scripts/show-mcp.sh   # MCP config
> ```

---

## Features

- **Auto-initialization**: Secrets generated automatically on first deployment
- **Key rotation scripts**: Safe rotation with --dry-run preview mode
- **Multi-platform**: Docker CLI, EasyPanel, Portainer, Coolify, etc.
- **MCP integration**: Built-in connection guide for Claude/Cursor

---

## Environment Variables

### Freely Changeable (restart required)

| Variable                                                    | Description          |
| ----------------------------------------------------------- | -------------------- |
| `SITE_URL`, `API_EXTERNAL_URL`, `SUPABASE_PUBLIC_URL` | Public URLs          |
| `STUDIO_DEFAULT_ORGANIZATION`, `STUDIO_DEFAULT_PROJECT` | Studio display names |
| `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD`              | Dashboard login      |
| `KONG_HTTP_PORT`, `KONG_HTTPS_PORT`                     | API Gateway ports    |
| Email/Phone settings,`OPENAI_API_KEY`, etc.               | All other settings   |

### Immutable After Deployment

> [!CAUTION]
> These values are stored internally. Changing `.env` alone will **break your system**.
> Use rotation scripts or deploy a new instance.

| Variable                           | Where Stored    | How to Change                   |
| ---------------------------------- | --------------- | ------------------------------- |
| `INSTANCE_NAME`                  | Container names | New instance required           |
| `POSTGRES_PASSWORD`              | 5 DB roles      | `rotate-postgres-password.sh` |
| `JWT_SECRET`                     | DB settings     | `rotate-jwt-secret.sh`        |
| `ANON_KEY`, `SERVICE_ROLE_KEY` | JWT tokens      | `rotate-jwt-secret.sh`        |
| `VAULT_ENC_KEY`                  | Supavisor       | `rotate-vault-key.sh`         |

See [docs/secrets-lifecycle.md](./docs/secrets-lifecycle.md) for rotation procedures.

---

## Architecture

```
                    ┌──────────────────────────────┐
                    │     Kong (API Gateway)       │
                    │      :8000 / :8443           │
                    └──────────────┬───────────────┘
                                   │
          ┌────────────┬───────────┼───────────┬────────────┐
          ▼            ▼           ▼           ▼            ▼
      ┌──────┐    ┌──────┐    ┌────────┐  ┌────────┐   ┌─────────┐
      │ Auth │    │ REST │    │Realtime│  │Storage │   │Functions│
      └──┬───┘    └──┬───┘    └───┬────┘  └───┬────┘   └────┬────┘
         └───────────┴────────────┼───────────┴─────────────┘
                                  ▼
                    ┌──────────────────────────────┐
                    │   Supavisor (Pooler)         │
                    │      :5432 / :6543           │
                    └──────────────┬───────────────┘
                                   ▼
                    ┌──────────────────────────────┐
                    │        PostgreSQL            │
                    └──────────────────────────────┘

Supporting: Studio, postgres-meta, ImgProxy, Vector, Analytics
```

---

## Scripts

All rotation scripts support `--dry-run` (preview) and `--allow-destructive` (execute).

| Script                          | Purpose            | Impact                             |
| ------------------------------- | ------------------ | ---------------------------------- |
| `show-env.sh`                 | Show env info      | Read-only (URLs, API keys, login)  |
| `show-mcp.sh`                 | Show MCP config    | Read-only (Claude/Cursor setup)    |
| `init-instance.sh`            | First-time setup   | Generates secrets                  |
| `check-health.sh`             | Verify services    | Read-only                          |
| `backup.sh`                   | Database backup    | Creates SQL dump                   |
| `reset.sh`                    | Full reset         | **Deletes all data**         |
| `rotate-postgres-password.sh` | Rotate DB password | ~30s downtime                      |
| `rotate-jwt-secret.sh`        | Rotate JWT         | **All sessions invalidated** |
| `rotate-vault-key.sh`         | Rotate Vault key   | **Pooler data destroyed**    |

```bash
# Preview changes first
./scripts/rotate-jwt-secret.sh --dry-run

# Execute with confirmation
./scripts/rotate-jwt-secret.sh --allow-destructive
```

> [!WARNING]
> Rotation scripts are for **dev/staging only**.
> For production, use blue/green deployment (see [docs/secrets-lifecycle.md](./docs/secrets-lifecycle.md)).

---

## MCP Integration (AI Assistant)

Connect your self-hosted Supabase to AI assistants (Claude, Cursor, etc.) using [supabase-mcp-sf](https://github.com/Song-JunHyeong/supabase-mcp-sf).

### Quick Setup

```bash
# Get your connection info
./scripts/show-mcp.sh
```

This outputs a ready-to-use configuration for your MCP client.

### Claude Desktop / Cursor Configuration

Add to your MCP configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`  
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "supabase-sf": {
      "command": "npx",
      "args": ["-y", "@jun-b/supabase-mcp-sf"],
      "env": {
        "SUPABASE_URL": "http://your-domain:8000",
        "SUPABASE_SERVICE_ROLE_KEY": "<your-service-role-key>",
        "SUPABASE_ANON_KEY": "<your-anon-key>"
      }
    }
  }
}
```

> [!TIP]
> Run `./scripts/show-mcp.sh` or check `docker logs supabase-mcp-guide` for pre-filled configuration.

### Available AI Tools

With MCP connected, your AI assistant can:

| Category | Tools |
|----------|-------|
| **Database** | `execute_sql`, `list_tables`, `apply_migration` |
| **Auth** | `list_users`, `create_user`, `generate_link` |
| **Storage** | `list_files`, `upload_file`, `create_signed_url` |
| **Functions** | `list_edge_functions`, `invoke_edge_function` |
| **Operations** | `check_health`, `backup_now`, `rotate_secret`, `get_stats` |
| **Docs** | `search_docs` |

### Example AI Prompts

```
"Show me all tables in my database"
"Create a new user with email test@example.com"
"Check the health of my Supabase instance"
"Create a database backup"
"List all Edge Functions"
```

### Security

> [!WARNING]
> The `SERVICE_ROLE_KEY` has full database access. 
> - Never expose MCP server to the internet
> - Use `--read-only` mode for safer AI interactions
> - Consider creating a dedicated AI agent role (see MCP docs)

---

## Repository Structure

```
supabase-sf/
├── docker-compose.yml    # Service orchestration
├── .env.example          # Environment template
├── scripts/              # Init, rotation, backup, health scripts
├── volumes/              # Persistent data (db, storage, functions)
├── docs/                 # Documentation
└── backups/              # Database backups (created by backup.sh)
```

---

## Versioning & Upstream

This repo is an **orchestration layer** on top of official Supabase Docker images.

### Tested Image Tags

| Service    | Tag                                        |
| ---------- | ------------------------------------------ |
| PostgreSQL | `supabase/postgres:15.8.1.085`           |
| Studio     | `supabase/studio:2025.11.26-sha-8f096b5` |
| Auth       | `supabase/gotrue:v2.183.0`               |
| Realtime   | `supabase/realtime:v2.65.3`              |
| Storage    | `supabase/storage-api:v1.32.0`           |

### Update Policy

- We track **stable releases**, not every patch
- Manual tag changes may break init/rotation scripts
- Upgrades require testing → open a PR with results

---

## Configuration

Key variables in `.env`:

| Variable                        | Description                 |
| ------------------------------- | --------------------------- |
| `POSTGRES_PASSWORD`           | Database password           |
| `JWT_SECRET`                  | JWT signing key (32+ chars) |
| `DASHBOARD_PASSWORD`          | Studio login password       |
| `SITE_URL`                    | Your frontend URL           |
| `API_EXTERNAL_URL`            | External API URL            |
| `STUDIO_DEFAULT_ORGANIZATION` | Studio org name             |
| `STUDIO_DEFAULT_PROJECT`      | Studio project name         |

---

## Maintenance

```bash
# Update images
docker compose pull
docker compose down && docker compose up -d

# Backup database
./scripts/backup.sh

# Full reset (deletes all data!)
./scripts/reset.sh
```

---

## Troubleshooting

```bash
# Check status
docker compose ps

# View logs
docker compose logs <service>

# Health check
./scripts/check-health.sh
```

| Issue                   | Cause                       | Fix                                       |
| ----------------------- | --------------------------- | ----------------------------------------- |
| 502 Bad Gateway         | Wrong port/service in panel | Set port to `8000`, service to `kong` |
| Auth fails to start     | JWT_SECRET mismatch         | Verify DB and .env match                  |
| 401 API errors          | Invalid API keys            | Check ANON_KEY/SERVICE_ROLE_KEY           |
| Pooler connection fails | Password mismatch           | Run rotation script                       |
| Cached old page         | Browser cache               | Use incognito mode or clear cache         |

---

## Links

- [Self-Hosting Docs](https://supabase.com/docs/guides/self-hosting/docker)
- [GitHub Discussions](https://github.com/orgs/supabase/discussions?discussions_q=is%3Aopen+label%3Aself-hosted)
- [Discord](https://discord.supabase.com)

---

## License

Apache 2.0 - [LICENSE](./LICENSE)
