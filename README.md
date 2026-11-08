# TrueSofts database backups

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

Restore into a **new, empty Supabase project first** and check it before touching production:

```bash
pg_restore --no-owner --no-privileges --data-only -n auth -d "<new project connection string>" backup.dump
pg_restore --no-owner --no-privileges -n public -d "<new project connection string>" backup.dump
```

Single sheets or tables can be pulled out with `pg_restore -t <table>`.
