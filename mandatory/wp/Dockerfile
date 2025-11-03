FROM debian:oldstable
RUN apt update -y && apt upgrade -y && apt -y install lsb-release apt-transport-https ca-certificates wget curl gosu
#RUN groupadd -r www-data && useradd -r -g www-data www-data --home-dir /var/www
RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
RUN echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list && apt policy php
RUN apt update -y && apt install -y php8.3 php8.3-fpm php8.3-cli php8.3-mysqli #php8.3-{bz2,curl,mbstring,intl}
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
RUN php wp-cli.phar --info && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp && mkdir "/var/www" && chown www-data:www-data /var/www
COPY ./mandatory/wp/docker-entrypoint.sh /usr/local/bin/
COPY ./mandatory/wp/www.conf /etc/php/8.3/fpm/pool.d/
RUN ["chmod", "+x", "/usr/local/bin/docker-entrypoint.sh"]
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

EXPOSE 9000