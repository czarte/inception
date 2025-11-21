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

  local createUser ="CREATE USER IF NOT EXISTS '$DB_USR'@'%' IDENTIFIED BY '$DB_PWD' ;"
  local userGrants ="GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%' ;"
  local flushPrivileges = "FLUSH PRIVILEGES;"

	read -r -d '' rootCreate <<-EOSQL || true
    CREATE USER 'root'@'${MARIADB_ROOT_HOST}' IDENTIFIED BY '${rootPasswordEscaped}' ;
    GRANT ALL ON *.* TO 'root'@'${MARIADB_ROOT_HOST}' WITH GRANT OPTION ;
    GRANT PROXY ON ''@'%' TO 'root'@'${MARIADB_ROOT_HOST}' WITH GRANT OPTION;
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
	_main "$@"
fi