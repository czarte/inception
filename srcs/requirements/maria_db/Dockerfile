FROM debian:oldstable

# Apt check + installing MariaDB + cleanup apt cache
RUN apt-get update && \
	apt-get install -y --no-install-recommends mariadb-server gettext && \
	apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

# Set MariaDB to listen on all interfaces - Otherwise wordpress can't connect
RUN sed -i "s/^bind-address\s*=.*$/bind-address = 0.0.0.0/" \
	/etc/mysql/mariadb.conf.d/50-server.cnf

#copy from:                 to:
COPY ./requirements/maria_db/50-server.cnf /etc/mysql/mariadb.conf.d/
COPY ./requirements/maria_db/nminimal-entrypoint.sh /usr/local/bin/
RUN ["chmod", "+x", "/usr/local/bin/nminimal-entrypoint.sh"]

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/nminimal-entrypoint.sh"]

#RUN groupadd -r mysql && useradd -r -g mysql mysql --home-dir /var/lib/mysql
#RUN apt-get update -y && apt-get install --no-install-recommends mariadb-server gosu -y
#
#VOLUME /var/lib/mysql
#
#COPY ./requirements/maria_db/50-server.cnf /etc/mysql/mariadb.conf.d/
#COPY ./requirements/maria_db/minimal-entrypoint.sh /usr/local/bin/
#RUN ["chmod", "+x", "/usr/local/bin/minimal-entrypoint.sh"]
#RUN ["chmod", "-R", "a+rwx", "/var/lib/mysql"]
##RUN ["chmod", "-R", "a+rwx", "/run/mysqld"]
#
#EXPOSE 3306
#ENTRYPOINT ["/usr/local/bin/minimal-entrypoint.sh"]
