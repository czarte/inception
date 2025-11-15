#!/bin/bash

wp core download --path=/var/www/public_html --locale=cs_CZ --allow-root
wp config create --path=/var/www/public_html --dbname=$DB_NAME --dbuser=$DB_USR --dbpass=$DB_PWD --dbhost=$DB_SRV --force --allow-root
wp core install --path=/var/www/public_html --url=$DOMAIN_NAME/ --title=$WP_TITLE --admin_user=$ADMIN_USER --admin_password=$ADMIN_PWD --admin_email=$ADMIN_EMAIL --skip-email --allow-root
wp user create --path=/var/www/public_html visitor visotor@42.fr --role=subscriber --user_pass=$USER_PWD --allow-root

/usr/sbin/php-fpm8.3 -F