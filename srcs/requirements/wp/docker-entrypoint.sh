#!/bin/bash

gosu www-data wp core download --path=/var/www/html --locale=cs_CZ
gosu www-data wp config create --path=/var/www/html --dbname=$DB_NAME --dbuser=$DB_USR --dbpass=$DB_PWD --dbhost=$DB_SRV --force --allow-root
gosu www-data wp core install --path=/var/www/html --url=$DOMAIN_NAME/ --title=$WP_TITLE --admin_user=$ADMIN_USER --admin_password=$ADMIN_PWD --admin_email=$ADMIN_EMAIL --skip-email --allow-root
gosu www-data wp user create --path=/var/www/html visitor visotor@42.fr --role=subscriber --user_pass=password

/usr/sbin/php-fpm8.3 -F