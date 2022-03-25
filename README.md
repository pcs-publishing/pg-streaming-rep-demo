# Postgres streaming replication demo

## Introduction

So long as the pre-requisites detailed below are met, this demo should _"just work"_.

There are two variables defined in `'.env'` that simply set the default `'postgres'` user password to `'postgres'` when the clusters are initialised, and sets the Docker Compose project name to `'demo'`. If necessary, you can change these to suit your environment, but that may affect the instructions below.

The version of Postgres used in this demo is `'10.19'`.

Be aware that the `'recovery.conf'` file was removed in versions of Postgres `'12+'`, where the options were merged into the main `'postgresql.conf'` file; if you're wanting to try this on versions of Postgres greater than `'11'`, you'll need to check the official docs, as there is a chance the config options will also have changed.

The steps below walk you through using the demo to set-up 2 clusters (`'master'` and `'replica'`) and configure streaming replication between them.

All the files needed for the demo are included in the repository and, with a working knowledge of Postgres and Docker, should be self-explanatory. Similarly, it should be easy enough to extrapolate the changes required to achieve streaming replication on regular clusters from the demo.

### Pre-requisites

- [Docker Engine](https://docs.docker.com/engine/install/) (tested on `v20.10`)
- [Docker Compose](https://docs.docker.com/compose/install/) (tested on `v2.2.3`)

> Depending on how you install Docker Compose, it will either be available as a plugin to the core `docker` command, invoked as `'docker compose'`, or as a stand-alone binary, invoked as `'docker-compose'` (note the hyphen).
>
> The instructions below assume a stand-alone binary install (`'docker-compose'`). Adjust as necessary if you're running with the plugin version.
>
> These are the versions the demo has been tested with, but they should also work with any recent combination of Docker / Docker Compose.
>
> The `'version'` set in `'docker-compose.yml'` is `'3.8'`; if you're running an older version of Docker Compose, you may need to change this.

### Reset

If you want to make sure none of the default resources used in this demo exist on your machine before you work through the steps below then run the following commands. It's fine if some of these error - it just means these resources don't exist in your local environment.

Similarly, you can use these commands to re-set the environment if anything goes wrong. Remember to take the environment down with `docker-compose down` though.

```bash
# remove data directory volumes
docker volume rm demo_master-data
docker volume rm demo_replica-data

# remove project network
docker network rm demo

# remove container image
docker rmi postgres:10.19-rep
```

---

## Build the environment

The environment consists of 2 Postgresql clusters (servers), `'master'` and `'replica'`.

If the base image (`'postgres:10.19-rep'`) does not exist, then it will be built automatically using `'postgres/Dockerfile'`.

Bringing up both `'master'` and `'replica'` for the first time will initialise a data directory for each cluster.

```bash
docker-compose up -d
```

## Seed the `'master'` cluster

Running the `'init.sh'` script bundled in the `'postgres:10.19-rep'` image will create an empty `'application'` database and configure an `'application'` user with the appropriate access permissions.

You can review the content of the script in `'postgres/init.sh'`.

```bash
docker-compose exec -u postgres master /var/lib/postgresql/scripts/init.sh
```

## Seed the `'replica'` cluster with a copy of `'master'`

We need to overwrite the data directory on the `'replica'` with a copy of the data directory from `'master'`.

We're going to shut `'replica'` down and mount its data volume (`'demo_replica-data'`) into an ephemeral `'postgres'` container, remove the current contents (which is just an empty cluster) and run [`'pg_basebackup'`](https://www.postgresql.org/docs/10/app-pgbasebackup.html) to take a copy from `'master'`.

We're then going to create the necessary config to let `'postgres'` know that this data directory is a replica and how it can source changes to keep the replica up to date once we start the cluster.

### Shut down the `'replica'`

```bash
docker stop demo-replica && docker rm demo-replica
```

### Spin up an ephemeral `'postgres'` container

```bash
docker run -itu postgres \
  -v demo_replica-data:/var/lib/postgresql/data \
  --network demo \
  --rm \
  postgres:10.19-rep \
  bash
```

> It's important that you leave the `'master'` service up and that you connect this ephemeral container to the same network the `'master'` node is connected to (`'--network demo'` in the command above).
>
> You won't be able to use `'pg_basebackup'` to copy the data directory from `'master'` if `'master'` is down or this container isn't connected to the same network.

### Remove the existing contents of the data directory

```bash
cd /var/lib/postgresql/data
rm -rf ./*
```

### Run `'pg_basebackup'` to copy the data directory from `'master'`

```bash
pg_basebackup -h master -D /var/lib/postgresql/data/ --progress -U replication -X stream
# when prompted, use 'replication' as the password - see 'postgres/init.sh'
```

### Create a `'recovery.conf'` file in the data directory

```bash
cd /var/lib/postgresql/data

echo "standby_mode = 'on'" > recovery.conf
echo "primary_conninfo = 'host=master port=5432 user=replication password=replication'" >> recovery.conf
echo "trigger_file = '/tmp/is_master'" >> recovery.conf
```

> The `'recovery.conf'` file tells `'postgres'` that this cluster is a replica of `'master'` and how to connect to the `'master`' node to retrieve additional `'WAL'` files needed to keep `'replica'` in sync with `'master`'.

### Exit the ephemeral container

```bash
CTRL+D
```

### Bring the `'replica'` online

```bash
docker-compose up -d
```

## Test replication

### Connect to `'master'` and make some changes

```bash
docker-compose exec -u postgres master psql
```

```sql
select * from pg_stat_activity where usename = 'replication';
-- there should be one replication slot in use by the 'replica' node

-- connect to the 'application' database and make some changes
\c application
create table test(code char(5));
insert into test values('abcd');
select * from test;
\q
```

### Connect to `'replica'` and confirm the changes have been replicated

```bash
docker-compose exec -u postgres replica psql
```

```sql
-- connect to the 'application' database and verify the changes have been replicated
\c application
select * from test;
\q
```

You should see a single row in the `'test'` table on `'replica'` matching the insert you did on `'master'`.

Congratulations, you now have streaming replication between two clusters configured and active.

---

## Additional info

### Configuration files

#### `'postgresql.conf'`

The configuration options, specific to streaming replication, that need to be set in `'postgresql.conf'` are given below.

These settings are pre-configured on both `'master'` and `'replica`' in this demo, but when configuring an existing cluster to be used in a replication topology, you'll need to make these changes and re-start the cluster.

```conf
wal_level = replica
max_wal_senders = 4
wal_keep_segments = 64
synchronous_standby_names = '*' # probably not required
hot_standby = on # ignored on 'master' node
```

`max_wal_senders` determines how many simultaneous replication connections the `'master'` node will accept. `2` is usually enough for a single `'replica'` node, but you'll need to increase this value if you want multiple replicas.

`wal_keep_segments` determines how many `WAL` files the `'master`' node will keep before allowing them to be removed.

Each `WAL` file is `16MB`, so `64` amounts to around `1GB` of transactional data to keep on the `'master'` node.

The actual value you need to use here will depend on how quickly your `'master'` cluster journals data (which will depend on your application and load), and how long you might expect a network partition or outage will keep your `'replica'` from reading `WAL` files from the `'master'`.

In normal operation, replication is almost instantaneous, so the `WAL` files are only required to allow a `'replica'` that has fallen behind to catch-up without having to re-initialise using `pg_basebackup`.

Full, hsitoric PITR (point in time recovery) can be achieved with the `archive_command` if required. The official documentation for PITR can be found [here](https://www.postgresql.org/docs/10/continuous-archiving.html)

`hot_standby` is ignored on the `'master'` node. `'replica'` nodes can have all of these config options set too though, so including it here makes for a consistent set of config options to be applied to any cluster joining the replication topology.

#### `'pg_hba.conf'`

The `'pg_hba.conf'` file used by this demo on both the `'master'` and `'replica'` nodes is given below.

```conf
# PostgreSQL Client Authentication Configuration File
# ===================================================
#
# Refer to the "Client Authentication" section in the PostgreSQL
# documentation for a complete description of this file.
#
# TYPE  DATABASE        USER            ADDRESS                METHOD
local   all             all                                    trust
host    all             all             127.0.0.1/32           trust
host    all             all             ::1/128                trust
#
# Allow trusted replication connections from localhost.
local   replication     all                                    trust
host    replication     all             127.0.0.1/32           trust
host    replication     all             ::1/128                trust
#
# Allow authenticated replication connections from any host.
host    replication     replication     0.0.0.0/0              md5
#
# Allow authenticated connections from containers on the docker network.
host    all             application     samenet                md5
host    all             application_ro  samenet                md5
#
# Allow authenticated postgres connections from the postgresql host.
host    all             postgres        samehost               md5

```

The _important_ entry from a streaming replication perspective is.

```conf
host    replication     replication     0.0.0.0/0              md5
```

This entry will allow password authenticated, replication connections from the `'replication'` user from _any_ host.

In a production environment, it is advised that connections be bound to the individual hosts in the replication topology.

---

## License

```
The MIT License (MIT)
Copyright © 2022 Press Computer Systems Ltd.

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the “Software”), to deal in the
Software without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
