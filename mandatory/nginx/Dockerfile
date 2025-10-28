FROM debian:stable
RUN apt-get clean && apt-get -y update && apt-get install -y systemctl curl gnupg2 ca-certificates lsb-release debian-archive-keyring
RUN curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
RUN gpg --gen-key --no-tty --batch && gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
RUN apt-get install -y nginx
#    && systemctl start nginx
CMD ["nginx", "-g", "daemon off;"]