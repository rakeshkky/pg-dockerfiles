#!/bin/bash
set -e

mkdir -p "$PGDATA"
chmod 700 "$PGDATA"
chown -R postgres "$PGDATA"

mkdir -p /run/postgresql
chmod g+s /run/postgresql
chown -R postgres /run/postgresql

export PG_VERSION_FILE=$PGDATA/PG_VERSION

# look specifically for PG_VERSION, as it is expected in the DB dir
if [ -s $PG_VERSION_FILE ]; then
  echo "Database is already initialised. The version is $(cat $PG_VERSION_FILE)"
  exit 0
fi

# Initialise database
eval "gosu postgres initdb $POSTGRES_INITDB_ARGS"

# check password first so we can output the warning before postgres
# messes it up
if [ "$POSTGRES_PASSWORD" ]; then
  pass="PASSWORD '$POSTGRES_PASSWORD'"
  authMethod=md5
else
  # The - option suppresses leading tabs but *not* spaces. :)
  cat >&2 <<-'EOWARN'
****************************************************
WARNING: No password has been set for the database.
         This will allow anyone with access to the
         Postgres port to access your database. In
         Docker's default configuration, this is
         effectively any other container on the same
         system.
         Use "-e POSTGRES_PASSWORD=password" to set
         it in "docker run".
****************************************************
EOWARN

  pass=
  authMethod=trust
fi

{ echo; echo "host all all all $authMethod"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null

# internal start of server in order to allow set-up using psql-client
# does not listen on external TCP/IP and waits until start finishes
gosu postgres pg_ctl -D "$PGDATA" \
  -o "-c listen_addresses='localhost'" \
  -w start

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-$POSTGRES_USER}"

psql=( psql -v ON_ERROR_STOP=1 )

if [ "$POSTGRES_DB" != 'postgres' ]; then
  "${psql[@]}" --username postgres <<-EOSQL
    CREATE DATABASE "$POSTGRES_DB" ;
EOSQL
  echo
fi

if [ "$POSTGRES_USER" = 'postgres' ]; then
  op='ALTER'
else
  op='CREATE'
fi

"${psql[@]}" --username postgres <<-EOSQL
  $op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
EOSQL
echo

psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

echo
for f in /docker-entrypoint-initdb.d/*; do
  case "$f" in
    *.sh)     echo "$0: running $f"; . "$f" ;;
    *.sql)    echo "$0: running $f"; "${psql[@]}" -f "$f"; echo ;;
    *.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
    *)        echo "$0: ignoring $f" ;;
  esac
  echo
done

gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop

echo
echo 'PostgreSQL init process complete; ready for start up.'
echo
