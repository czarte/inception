#!/bin/bash

echo "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%' ;" > /tmp/db1.sql
echo "FLUSH PRIVILEGES;" >> /tmp/db1.sql
mariadbd start
mariadb -u root --password=rootpassword < /tmp/db1.sql
exec mariadbd restart