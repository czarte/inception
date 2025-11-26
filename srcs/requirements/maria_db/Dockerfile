FROM debian:oldstable

RUN groupadd -r mysql && useradd -r -g mysql mysql --home-dir /var/lib/mysql
RUN apt-get update -y && apt-get install mariadb-server gosu -y

VOLUME /var/lib/mysql

COPY ./requirements/maria_db/50-server.cnf /etc/mysql/mariadb.conf.d/
COPY ./requirements/maria_db/nminimal-entrypoint.sh /usr/local/bin/
RUN ["chmod", "+x", "/usr/local/bin/nminimal-entrypoint.sh"]
RUN ["chmod", "-R", "a+rwx", "/var/lib/mysql"]
#RUN ["chmod", "-R", "a+rwx", "/run/mysqld"]
#ENTRYPOINT ["/usr/local/bin/minimal-entrypoint.sh"]
EXPOSE 3306
CMD ["/usr/local/bin/nminimal-entrypoint.sh"]
