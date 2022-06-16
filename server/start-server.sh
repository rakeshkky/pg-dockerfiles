#!/bin/bash
set -e

# If continuous backup related env vars are passed, set them up
if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
  echo "Hasura Backup System: Continuous backup is enabled"
  echo "Hasura Backup System: Creating required directories"
  # Assumption: the group is trusted to read secret information
  umask u=rwx,g=rx,o=
  mkdir -p /etc/wal-e.d/env
  echo "Hasura Backup System: Setting up credentials"
  echo "$WALE_S3_PREFIX"        > /etc/wal-e.d/env/WALE_S3_PREFIX
  echo "$AWS_ACCESS_KEY_ID"     > /etc/wal-e.d/env/AWS_ACCESS_KEY_ID
  echo "$AWS_SECRET_ACCESS_KEY" > /etc/wal-e.d/env/AWS_SECRET_ACCESS_KEY
  echo "$AWS_REGION"            > /etc/wal-e.d/env/AWS_REGION
  chown -R root:postgres /etc/wal-e.d
fi

if [ "$1" = 'postgres' ]; then
    mkdir -p "$PGDATA"
    chmod 700 "$PGDATA"
    chown -R postgres "$PGDATA"

    mkdir -p /run/postgresql
    chmod g+s /run/postgresql
    chown -R postgres /run/postgresql
    exec gosu postgres "$@"
else
    exec "$@"
fi
