# http://phusion.github.io/baseimage-docker/
# https://github.com/phusion/baseimage-docker/blob/master/Changelog.md
FROM phusion/baseimage:0.9.19

MAINTAINER Brian Fisher <tbfisher@gmail.com>

RUN locale-gen en_US.UTF-8
ENV LANG       en_US.UTF-8
ENV LC_ALL     en_US.UTF-8

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

# Upgrade OS
RUN apt-get update && apt-get upgrade -y -o Dpkg::Options::="--force-confold"

# PHP
RUN add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
        php-pear          \
        php7.3-bcmath     \
        php7.3-cli        \
        php7.3-common     \
        php7.3-curl       \
        php7.3-dev        \
        php7.3-fpm        \
        php7.3-gd         \
        php7.3-imagick    \
        php7.3-imap       \
        php7.3-intl       \
        php7.3-json       \
        php7.3-ldap       \
        php7.3-mbstring   \
        php7.3-memcache   \
        php7.3-mysql      \
        php7.3-opcache    \
        php7.3-readline   \
        # php7.3-redis      \
        php7.3-sqlite     \
        php7.3-tidy       \
        php7.3-xdebug     \
        php7.3-xml        \
        php7.3-zip
        # php7.3-xhprof

# phpredis
ENV PHPREDIS_VERSION='3.0.0'
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
        git
RUN git clone -b $PHPREDIS_VERSION --depth 1 https://github.com/phpredis/phpredis.git /usr/local/src/phpredis
RUN cd /usr/local/src/phpredis && \
    phpize      && \
    ./configure && \
    make clean  && \
    make        && \
    make install
COPY ./conf/php/mods-available/redis.ini /etc/php/7.3/mods-available/redis.ini

# NGNIX
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
        nginx

# SSH (for remote drush)
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
        openssh-server
RUN dpkg-reconfigure openssh-server

# sSMTP
# note php is configured to use ssmtp, which is configured to send to mail:1025,
# which is standard configuration for a mailhog/mailhog image with hostname mail.
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
        ssmtp

# Drush, console
RUN cd /usr/local/bin/ && \
    curl http://files.drush.org/drush.phar -L -o drush && \
    chmod +x drush
COPY ./conf/drush/drush-remote.sh /usr/local/bin/drush-remote
RUN chmod +x /usr/local/bin/drush-remote
RUN cd /usr/local/bin/ && \
    curl https://drupalconsole.com/installer -L -o drupal && \
    chmod +x drupal

# Required for drush, convenience utilities, etc.
RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install --yes \
        git                 \
        mysql-client        \
        screen

# Configure PHP
RUN mkdir /run/php
RUN cp /etc/php/7.3/fpm/php.ini /etc/php/7.3/fpm/php.ini.bak
COPY ./conf/php/fpm/php.ini-development /etc/php/7.3/fpm/php.ini
# COPY /conf/php/fpm/php.ini-production /etc/php/7.3/fpm/php.ini
RUN cp /etc/php/7.3/fpm/pool.d/www.conf /etc/php/7.3/fpm/pool.d/www.conf.bak
COPY /conf/php/fpm/pool.d/www.conf /etc/php/7.3/fpm/pool.d/www.conf
RUN cp /etc/php/7.3/cli/php.ini /etc/php/7.3/cli/php.ini.bak
COPY /conf/php/cli/php.ini-development /etc/php/7.3/cli/php.ini
# COPY /conf/php/cli/php.ini-production /etc/php/7.3/cli/php.ini
# Prevent php warnings
RUN sed -ir 's@^#@//@' /etc/php/7.3/mods-available/*
RUN phpenmod \
    redis
    # xhprof

# Configure NGINX
RUN cp -r /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
COPY ./conf/nginx/default-development /etc/nginx/sites-available/default
# COPY ./conf/nginx/default-production /etc/nginx/sites-available/default
RUN cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
COPY ./conf/nginx/nginx.conf /etc/nginx/nginx.conf

# Configure sshd
RUN cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
COPY ./conf/ssh/sshd_config /etc/ssh/sshd_config
RUN cp /etc/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf.bak
COPY ./conf/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf

# Configure directories for drupal.
RUN mkdir /var/www_files && \
    mkdir -p /var/www_files/public && \
    mkdir -p /var/www_files/private && \
    chown -R www-data:www-data /var/www_files
VOLUME /var/www_files
# Virtualhost is configured to serve from /var/www/web.
RUN mkdir -p /var/www/web && \
    echo '<?php phpinfo();' > /var/www/web/index.php && \
    chgrp www-data /var/www_files && \
    chmod 775 /var/www_files

# https://github.com/phusion/baseimage-docker/pull/339
# https://github.com/phusion/baseimage-docker/pull/341
RUN sed -i 's/syslog/adm/g' /etc/logrotate.conf

# Use baseimage-docker's init system.
ADD init/ /etc/my_init.d/
RUN chmod -v +x /etc/my_init.d/*.sh
ADD services/ /etc/service/
RUN chmod -v +x /etc/service/*/run

# Node and backstop
RUN curl "https://deb.nodesource.com/setup_11.x" -o "setup_11.x" && \
  chmod +x setup_11.x && \
  ./setup_11.x && \
  rm setup_11.x && \
  apt-get install nodejs -y

ENV \
    PHANTOMJS_VERSION=2.1.7 \
    CASPERJS_VERSION=1.1.4 \
    SLIMERJS_VERSION=0.10.3 \
    BACKSTOPJS_VERSION=3.5.16 \
    # Workaround to fix phantomjs-prebuilt installation errors
    # See https://github.com/Medium/phantomjs/issues/707
    NPM_CONFIG_UNSAFE_PERM=true

# Base packages
RUN apt-get update && \
  apt-get install -y git sudo software-properties-common python-software-properties wget

RUN sudo npm install -g --unsafe-perm=true --allow-root phantomjs@${PHANTOMJS_VERSION}
RUN sudo npm install -g --unsafe-perm=true --allow-root casperjs@${CASPERJS_VERSION}
RUN sudo npm install -g --unsafe-perm=true --allow-root slimerjs@${SLIMERJS_VERSION}
RUN sudo npm install -g --unsafe-perm=true --allow-root backstopjs@${BACKSTOPJS_VERSION}

RUN wget https://dl-ssl.google.com/linux/linux_signing_key.pub && sudo apt-key add linux_signing_key.pub
RUN sudo add-apt-repository "deb http://dl.google.com/linux/chrome/deb/ stable main"

RUN apt-get -y update && \
  apt-get -y install google-chrome-stable

EXPOSE 80 22

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
