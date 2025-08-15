FROM php:8.4-fpm-alpine

# OCI image labels for metadata
LABEL org.opencontainers.image.title="PHP 8.4 FPM (Alpine) for Symfony" \
      org.opencontainers.image.description="PHP 8.4 FPM on Alpine with common extensions, APCu, Composer, fcron, and developer tools." \
      org.opencontainers.image.version="8.4-fpm-alpine" \
      org.opencontainers.image.licenses="MIT"

# Install PHP runtime and build dependencies in fewer layers
RUN set -eux; \
    apk add --no-cache --virtual .php-build-deps \
        $PHPIZE_DEPS bzip2-dev libxml2-dev libedit-dev libxslt-dev icu-dev sqlite-dev libzip-dev linux-headers \
        libpng-dev libjpeg-turbo-dev freetype-dev \
    && apk add --no-cache --virtual .php-runtime-deps \
        freetype libpng libjpeg-turbo libbz2 libzip libxslt icu \
    && NPROC="$(getconf _NPROCESSORS_ONLN)" \
    && docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"${NPROC}" \
        gd bz2 dom exif fileinfo intl opcache pcntl pdo pdo_mysql pdo_sqlite session simplexml xml xsl zip \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && apk del .php-build-deps \
    && rm -rf /tmp/*

# Composer (deterministic): use official binary
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Tools: git/ssh, rsync, DB client, timezone, uid helpers
RUN apk add --no-cache git openssh-client rsync mariadb-client tzdata shadow su-exec

# fcron via apk (smaller, faster than building from source)
RUN apk add --no-cache fcron
ADD fcron.conf /usr/local/etc
ADD echomail /usr/local/bin
RUN chown root:fcron /usr/local/etc/fcron.conf && \
    chmod 644 /usr/local/etc/fcron.conf

# Default configuration for fpm
# Project-specific ini can be added with COPY ./php-ini-overrides.ini /usr/local/etc/php/conf.d/
COPY ./zz-fpm.conf /usr/local/etc/php-fpm.d/

# Base php ini
COPY ./docker-base.ini /usr/local/etc/php/conf.d/

# Disable xdebug by default and add a script to reactivate
# Just add a COPY ./xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini.bak in your project
# COPY xdebug.sh /
# RUN mv /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini.bak

# Cache composer downloads in a volume (align with Composer home)
VOLUME /home/www-data/.composer

# Script to wait for db
COPY wait-for /usr/local/bin

COPY entrypoint-cron /usr/local/bin
COPY entrypoint-chuid /usr/local/bin

# Healthcheck: ensure php-fpm master process is running
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD pgrep -f 'php-fpm: master process' > /dev/null || exit 1

ENTRYPOINT ["entrypoint-chuid"]
CMD ["php-fpm"]
