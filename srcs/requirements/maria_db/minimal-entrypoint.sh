#!/bin/bash
#set -x

mysql_log() {
	local type="$1"; shift
	printf '%s [%s] [Entrypoint]: %s\n' "$(date --rfc-3339=seconds)" "$type" "$*"
}
mysql_note() {
	mysql_log Note "$@"
}
mysql_warn() {
	mysql_log Warn "$@" >&2
}
mysql_error() {
	mysql_log ERROR "$@" >&2
	exit 1
}

docker_temp_server_start() {
	"$@" --skip-networking --default-time-zone=SYSTEM --socket="${SOCKET}" --wsrep_on=OFF \
		--expire-logs-days=0 \
		--skip-slave-start \
		--loose-innodb_buffer_pool_load_at_startup=0 \
		&
	declare -g MARIADB_PID
	MARIADB_PID=$!
	mysql_note "Waiting for server startup"
	# only use the root password if the database has already been initialized
	# so that it won't try to fill in a password file when it hasn't been set yet
	extraArgs=()
	if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
		extraArgs+=( '--dont-use-mysql-root-password' )
	fi
	local i
	for i in {30..0}; do
		if docker_process_sql "${extraArgs[@]}" --database=mysql \
			<<<'SELECT 1' &> /dev/null; then
			break
		fi
		sleep 1
	done
	if [ "$i" = 0 ]; then
		mysql_error "Unable to start server."
	fi
}

# Stop the server. When using a local socket file mariadb-admin will block until
# the shutdown is complete.
docker_temp_server_stop() {
	kill "$MARIADB_PID"
	wait "$MARIADB_PID"
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}
# Execute sql script, passed via stdin
# usage: docker_process_sql [--dont-use-mysql-root-password] [mysql-cli-args]
#    ie: docker_process_sql --database=mydb <<<'INSERT ...'
#    ie: docker_process_sql --dont-use-mysql-root-password --database=mydb <my-file.sql
docker_process_sql() {
	if [ '--dont-use-mysql-root-password' = "$1" ]; then
		shift
		MYSQL_PWD='' docker_exec_client "$@"
	else
		MYSQL_PWD=$MARIADB_ROOT_PASSWORD docker_exec_client "$@"
	fi
}

mysql_get_config() {
	local conf="$1"; shift
	"$@" "${_verboseHelpArgs[@]}" 2>/dev/null \
		| awk -v conf="$conf" '$1 == conf && /^[^ \t]/ { sub(/^[^ \t]+[ \t]+/, ""); print; exit }'
	# match "datadir      /some/path with/spaces in/it here" but not "--xyz=abc\n     datadir (xyz)"
}

docker_exec_client() {
	# args sent in can override this db, since they will be later in the command
	if [ -n "$MYSQL_DATABASE" ]; then
		set -- --database="$MYSQL_DATABASE" "$@"
	fi
	mariadb --protocol=socket -uroot -hlocalhost --socket="/run/mysqld/mysqld.sock" "$@"
}

docker_setup_db() {
	# Load timezone info into database
	if [ -z "$MARIADB_INITDB_SKIP_TZINFO" ]; then
		# --skip-write-binlog usefully disables binary logging
		# but also outputs LOCK TABLES to improve the IO of
		# Aria (MDEV-23326) for 10.4+.
		docker_process_sql --dont-use-mysql-root-password --database=mysql
		# tell docker_process_sql to not use MYSQL_ROOT_PASSWORD since it is not set yet
	fi

  local mysqlAtLocalhost=
  local mysqlAtLocalhostGrants=
  # Install mysql@localhost user
  if [ -n "$MARIADB_MASTER_HOST" ]; then
		read -r -d '' mysqlAtLocalhost <<-EOSQL || true
		CREATE USER mysql@localhost IDENTIFIED VIA unix_socket;
		EOSQL
		mysqlAtLocalhostGrants="GRANT ALL ON *.* TO mysql@localhost;";
  fi

  local createDatabase=
  # Creates a custom database and user if specified
  if [ -n "$MARIADB_DATABASE" ]; then
    mysql_note "Creating database ${DB_NAME}"
    createDatabase="CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
  fi

  local createUser="CREATE USER IF NOT EXISTS '$DB_USR'@'%' IDENTIFIED BY '$DB_PWD' ;"
  local userGrants="GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%' ;"
  local flushPrivileges="FLUSH PRIVILEGES;"

	read -r -d '' rootCreate <<-EOSQL || true
		CREATE USER 'root'@'${MARIADB_ROOT_HOST}' IDENTIFIED BY '${rootPasswordEscaped}' ; \
		GRANT ALL ON *.* TO 'root'@'${MARIADB_ROOT_HOST}' WITH GRANT OPTION ; \
		GRANT PROXY ON ''@'%' TO 'root'@'${MARIADB_ROOT_HOST}' WITH GRANT OPTION; \
	EOSQL

  docker_process_sql --dont-use-mysql-root-password --database=mysql --binary-mode <<-EOSQL
  		-- Securing system users shouldn't be replicated
  		SET @orig_sql_log_bin= @@SESSION.SQL_LOG_BIN;
  		SET @@SESSION.SQL_LOG_BIN=0;
                  -- we need the SQL_MODE NO_BACKSLASH_ESCAPES mode to be clear for the password to be set
  		SET @@SESSION.SQL_MODE=REPLACE(@@SESSION.SQL_MODE, 'NO_BACKSLASH_ESCAPES', '');

  		DROP USER IF EXISTS root@'127.0.0.1', root@'::1';
  		EXECUTE IMMEDIATE CONCAT('DROP USER IF EXISTS root@\'', @@hostname,'\'');

  		${rootCreate}
  		${mysqlAtLocalhost}
  		${mysqlAtLocalhostGrants}
  		-- end of securing system users, rest of init now...
  		SET @@SESSION.SQL_LOG_BIN=@orig_sql_log_bin;
  		-- create users/databases
  		${createDatabase}
  		${createUser}
  		${createReplicaUser}
  		${userGrants}
  		${flushPrivileges}
		EOSQL
}

_main() {
	# if command starts with an option, prepend mariadbd
	if [ "${1:0:1}" = '-' ]; then
		set -- mariadbd "$@"
	fi

	#ENDOFSUBSTITUTIONS
	# skip setup if they aren't running mysqld or want an option that stops mysqld
	if [ "$1" = 'mariadbd' ] || [ "$1" = 'mysqld' ] ; then
		mysql_note "Entrypoint script for MariaDB Server ${MARIADB_VERSION} started."
		mysql_note "MARIADB_ROOT_PASSWORD_HASH ${MARIADB_ROOT_PASSWORD_HASH}"

		# If container is started as root user, restart as dedicated mysql user
		if [ "$(id -u)" = "0" ]; then
		  chown -R mysql:mysql "$DATADIR"
      chown -R mysql:mysql /var/lib/mysql
      chown -R mysql:mysql /run/mysqld
			mysql_note "Switching to dedicated user 'mysql'"
			exec gosu mysql "${BASH_SOURCE[0]}" "$@"
		fi

		# there's no database, so it needs to be initialized
		if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
			docker_setup_db
		fi
	fi
	exec "$@"
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
	declare -g DATADIR SOCKET PORT
	DATADIR="$(mysql_get_config 'datadir' "$@")"
	SOCKET="$(mysql_get_config 'socket' "$@")"
	PORT="$(mysql_get_config 'port' "$@")"
	if [! -f "/var/lib/mysql/mariadb_installed"]; then
	  if [ ! -d "/var/lib/mysql/mysql" ]; then
            mysql_install_db --user=mysql --datadir=/var/lib/mysql
    fi
	  docker_temp_server_start
    docker_setup_db
    touch "/var/lib/mysql/mariadb_installed"
  fi
  exec mysqld_safe
  #exec "$@"
#	_main "$@"
fi