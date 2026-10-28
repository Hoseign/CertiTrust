FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    git \
    curl \
    libcurl4-openssl-dev \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libpq-dev \
    libgmp-dev \
    libicu-dev \
    zip \
    unzip \
    && docker-php-ext-install curl pdo pdo_mysql pdo_pgsql gmp mbstring exif pcntl bcmath gd xml dom intl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www
COPY CertiTrust/ /var/www/

RUN composer install --no-dev --optimize-autoloader --ignore-platform-reqs \
    && chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache

EXPOSE 10000

CMD php artisan migrate --force && (php artisan queue:work --sleep=1 --tries=1 --timeout=120 &) && exec php artisan serve --host=0.0.0.0 --port=${PORT:-10000}