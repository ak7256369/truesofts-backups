# TrueSofts database backups

The Supabase database starts this job every hour, using a GitHub token kept in its Vault as
`github_backup_token`. If that token expires, create a new one (Actions: read and write, this
repository only) and update the Vault; until then only the 6-hourly fallback runs.

Every hour this repository dumps the TrueSofts Supabase database, checks the dump, encrypts it
and stores it under **Releases**: `hourly` (7 days) and `daily` (30 days). A failed run emails
the repository owner.

Backups are encrypted with `public-key.asc`. Only the matching **private key** can open them,
and it is not in this repository. Without it the backups cannot be read by anyone.

## Restoring

Needs `gpg`, PostgreSQL 17 client tools, and the private key file.

```bash
gpg --import TRUESOFTS-BACKUP-PRIVATE-KEY.asc
gpg --output backup.dump --decrypt truesofts-YYYY-MM-DD_HH-MM.dump.gpg
pg_restore -l backup.dump          # see what is inside
```

Restore into a **new, empty Supabase project** on PostgreSQL 17, then check it before pointing
the app at it. These exact steps were tested on 2026-11-08 and matched live data, logins,
structure and permissions. Set `PGHOST`, `PGPORT=5432`, `PGUSER`, `PGPASSWORD`, `PGDATABASE=postgres`
and `PGSSLMODE=require` from the new project's **Session pooler** details first.

```bash
psql -c 'create extension if not exists btree_gist with schema extensions'
psql -c 'create schema if not exists supabase_migrations'

# 1. Accounts. This reports errors for identities, mfa_amr_claims and schema_migrations:
#    that is expected, and the next command loads identities now that users exist.
pg_restore --no-owner --no-privileges --data-only -n auth -d postgres backup.dump
pg_restore --no-owner --no-privileges --data-only -n auth -t identities -d postgres backup.dump

# 2. App tables and data. "permission denied to change default privileges" is expected.
pg_restore --no-owner -n public -d postgres backup.dump

# 3. The trigger on auth.users, and migration history
pg_restore -l backup.dump | grep ' TRIGGER auth users' > trigger.list
pg_restore --no-owner -L trigger.list -d postgres backup.dump
pg_restore --no-owner -n supabase_migrations -d postgres backup.dump

# 4. REQUIRED for security: new projects let anonymous visitors use every function and table,
#    so remove that and put back only the permissions the backup recorded.
for kind in functions tables sequences; do
  psql -c "revoke all on all $kind in schema public from anon, authenticated, service_role"
done
pg_restore -l backup.dump | grep -E ' ACL public (FUNCTION|TABLE|SEQUENCE) ' > acl.list
pg_restore --no-owner -L acl.list -d postgres backup.dump
```

To go live on the restored project, set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to the new
project in Vercel, redeploy, and update the Site URL under Authentication settings. Everyone
signs in again with their existing passwords. Update `backup.sh` to back up the new project.
