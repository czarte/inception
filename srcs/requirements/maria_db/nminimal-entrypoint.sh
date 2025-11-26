#!/bin/bash
set -e

docker_exec_client() {
	# args sent in can override this db, since they will be later in the command
	if [ -n "$MYSQL_DATABASE" ]; then
		set -- --database="$MYSQL_DATABASE" "$@"
	fi
	mariadb --protocol=socket -uroot -hlocalhost --socket="/run/mysqld/mysqld.sock" "$@"
}

docker_process_sql() {
	if [ '--dont-use-mysql-root-password' = "$1" ]; then
		shift
		MYSQL_PWD='' docker_exec_client "$@"
	else
		MYSQL_PWD=$MARIADB_ROOT_PASSWORD docker_exec_client "$@"
	fi
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
		EOSQL
}

docker_setup_wp() {
	local createDatabase=
    # Creates a custom database and user if specified
    if [ -n "$MARIADB_DATABASE" ]; then
      mysql_note "Creating database ${DB_NAME}"
      createDatabase="CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
    fi

    local createUser="CREATE USER IF NOT EXISTS '$DB_USR'@'%' IDENTIFIED BY '$DB_PWD' ;"
    local userGrants="GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%' ;"
    local flushPrivileges="FLUSH PRIVILEGES;"
	docker_process_sql --dont-use-mysql-root-password --database=mysql --binary-mode <<-EOSQL
			-- create users/databases
			${createDatabase}
			${createUser}
			${createReplicaUser}
			${userGrants}
			${flushPrivileges}
		EOSQL
}

# Check if this is first time setup - look for a more specific marker
if [ ! -f "/var/lib/mysql/inception_initialized" ]; then
    # Initialize MariaDB data directory if it doesn't exist
    if [ ! -d "/var/lib/mysql/mysql" ]; then
        mysql_install_db --user=mysql --datadir=/var/lib/mysql
    fi

    # Start MariaDB temporarily
    mysqld_safe --skip-networking &
    pid="$!"

    # Wait 1s in loop for server to be up
    until mysqladmin ping --silent; do
        sleep 1
    done

    docker_setup_db
    docker_setup_wp

    # Create marker file to indicate initialization is complete
    touch /var/lib/mysql/inception_initialized

    # Shutdown temporary server
    mysqladmin -u root -p"$MYSQL_ROOT_PASSWORD" shutdown || true
    wait "$pid" || true
fi

# Start MariaDB in foreground (normal mode)
exec mysqld_safe