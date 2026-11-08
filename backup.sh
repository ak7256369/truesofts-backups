#!/usr/bin/env bash
# Dumps the database, checks the dump is real, encrypts it, stores it and trims old copies.
set -euo pipefail

HOST=aws-0-ap-northeast-2.pooler.supabase.com
USER_NAME=postgres.cnkoxudoyzxtlwgezwlj
HOURLY_DAYS=7
DAILY_DAYS=30

stamp=$(TZ=Asia/Karachi date +%Y-%m-%d_%H-%M)
day=${stamp%_*}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dump="$work/truesofts-$stamp.dump"

pg() {
  docker run --rm -e PGPASSWORD="$SUPABASE_DB_PASSWORD" -v "$work:/work" postgres:17-alpine "$@"
}

# Application data plus accounts; login sessions and logs are left out on purpose
pg pg_dump -h "$HOST" -p 5432 -U "$USER_NAME" -d postgres -Fc \
  -n public -n auth -n storage -n supabase_migrations \
  --exclude-table-data='auth.sessions' --exclude-table-data='auth.refresh_tokens' \
  --exclude-table-data='auth.audit_log_entries' --exclude-table-data='auth.flow_state' \
  -f "/work/$(basename "$dump")"

# Never store a broken backup: the main tables must be in it
toc="$work/toc.txt"
pg pg_restore -l "/work/$(basename "$dump")" > "$toc"
for table in 'public sheet_snapshots' 'public interviews' 'public workbooks' 'public profiles' 'auth users'; do
  grep -q "TABLE DATA $table " "$toc" || { echo "Backup is missing: $table"; exit 1; }
done
echo "Dump OK: $(wc -c < "$dump") bytes, $(grep -c 'TABLE DATA' "$toc") tables"

# Encrypted with the public key only: this job cannot read its own backups
gpg --batch --quiet --import public-key.asc
encrypted="$dump.gpg"
gpg --batch --yes --trust-model always -r backups@truesofts.invalid -o "$encrypted" --encrypt "$dump"
rm -f "$dump"

ensure_release() {
  gh release view "$1" >/dev/null 2>&1 || gh release create "$1" --title "$2" --notes "Encrypted backups." --latest=false
}
ensure_release hourly "Hourly backups (kept $HOURLY_DAYS days)"
ensure_release daily "Daily backups (kept $DAILY_DAYS days)"

gh release upload hourly "$encrypted"

# The first backup of each day is also kept as the daily copy
if ! gh release view daily --json assets --jq '.assets[].name' | grep -q "truesofts-$day"; then
  gh release upload daily "$encrypted"
fi

# Old copies go only after the new one is safely stored
trim() {
  local cutoff
  cutoff=$(date -u -d "$2 days ago" +%Y-%m-%dT%H:%M:%SZ)
  gh release view "$1" --json assets --jq ".assets[] | select(.createdAt < \"$cutoff\") | .name" |
    while read -r name; do gh release delete-asset "$1" "$name" --yes; done
}
trim hourly "$HOURLY_DAYS"
trim daily "$DAILY_DAYS"
echo "Stored $(basename "$encrypted")"
