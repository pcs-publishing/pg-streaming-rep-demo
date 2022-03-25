#!/usr/bin/env bash
set -e -u -o pipefail

DATABASES=(
  "application"
)

ROLES=(
  "application"
)

function main {
  for role in ${ROLES[@]}; do sql "CREATE ROLE ${role} WITH LOGIN PASSWORD '${role}'"; done
  sql "CREATE USER replication REPLICATION LOGIN ENCRYPTED PASSWORD 'replication';"

  for db in ${DATABASES[@]}; do
    sql "DROP DATABASE IF EXISTS ${db};"
    sql "CREATE DATABASE ${db};"
    role="public"; revoke_all_permissions_from_role
  done

  for db in ${DATABASES[@]}; do
    for role in ${ROLES[@]}; do
      revoke_all_permissions_from_role
      grant_connect_database_permission_to_role
    done
    role="application"; grant_read_write_role
    role="application"; set_ownership
  done
}

function  sql {
  cmd="${1}"
  ctx="${2:-postgres}"
  echo "running command: '${cmd}' in database: '${ctx}'"
  psql -qAt -d "${ctx}" -c "${cmd}"
}

function revoke_all_permissions_from_role {
  sql "REVOKE ALL ON SCHEMA public FROM ${role};" "${db}"
  sql "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM ${role};" "${db}"
  sql "REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM ${role};" "${db}"
  sql "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM ${role};" "${db}"
  sql "REVOKE ALL ON DATABASE ${db} FROM ${role};" "${db}"
}

function grant_connect_database_permission_to_role {
  sql "GRANT CONNECT ON DATABASE ${db} TO ${role};" "${db}"
}

function grant_read_only_role {
  sql "GRANT USAGE ON SCHEMA public TO ${role};" "${db}"
  sql "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${role};" "${db}"
  sql "GRANT SELECT,USAGE ON ALL SEQUENCES IN SCHEMA public TO ${role};" "${db}"
  sql "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ${role};" "${db}"
  sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${role};" "${db}"
  sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO ${role};" "${db}"
  sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO ${role};" "${db}"
}

function grant_read_write_role {
  sql "GRANT ALL ON SCHEMA public TO ${role};" "${db}"
  sql "GRANT ALL ON ALL TABLES IN SCHEMA public TO ${role};" "${db}"
  sql "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${role};" "${db}"
  sql "GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO ${role};" "${db}"
  sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${role};" "${db}"
  sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ${role};" "${db}"
  sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO ${role};" "${db}"
}

function set_ownership {
  sql "ALTER DATABASE ${db} OWNER TO ${role}" "${db}"
  #
  TABLES=$(psql -qAt -d ${db} -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';")
  for t in ${TABLES}; do sql "ALTER TABLE \"${t}\" OWNER TO ${role}" "${db}"; done
  #
  SEQUENCES=$(psql -qAt -d ${db} -c "SELECT sequencename FROM pg_sequences WHERE schemaname = 'public';")
  for s in ${SEQUENCES}; do sql "ALTER TABLE \"${s}\" OWNER TO ${role}" "${db}"; done
}

main
