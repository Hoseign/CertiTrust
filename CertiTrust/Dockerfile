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
    unzip

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install curl pdo pdo_mysql pdo_pgsql gmp mbstring exif pcntl bcmath gd xml dom intl

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www
COPY . /var/www

RUN composer install --no-dev --optimize-autoloader --ignore-platform-reqs

RUN chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache

EXPOSE 10000

CMD php artisan migrate --force && (php artisan queue:work --sleep=1 --tries=1 --timeout=120 &) && exec php artisan serve --host=0.0.0.0 --port=${PORT:-10000}