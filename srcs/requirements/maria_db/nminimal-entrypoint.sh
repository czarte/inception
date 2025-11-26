#!/bin/bash

if [ "$(id -u)" = "0" ]; then
	mkdir "/run/mysqld/"
	mkdir "/var/log/mysql/"
	chown mysql:mysql "/var/log/mysql"
	chown mysql:mysql "/run/mysqld"
	exec gosu mysql "${BASH_SOURCE[0]}" "$@"
fi

service mariadb start --skip-networking --default-time-zone=SYSTEM --socket="${SOCKET}" --wsrep_on=OFF \
                      		--expire-logs-days=0 \
                      		--skip-slave-start \
                      		--loose-innodb_buffer_pool_load_at_startup=0

echo "CREATE DATABASE IF NOT EXISTS $DB_NAME ;" > /tmp/db1.sql
echo "CREATE USER IF NOT EXISTS '$DB_USR'@'%' IDENTIFIED BY '$DB_PWD' ;" >> /tmp/db1.sql
echo "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USR'@'%' ;" >> /tmp/db1.sql
echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' ;" >> /tmp/db1.sql
echo "FLUSH PRIVILEGES;" >> /tmp/db1.sql

mariadb < /tmp/db1.sql

service mariadb restart