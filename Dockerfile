FROM php:8.2-fpm
RUN apt-get update && apt-get install -y git curl libpng-dev libonig-dev libxml2-dev libpq-dev zip unzip
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
RUN docker-php-ext-install pdo pdo_pgsql mbstring exif pcntl bcmath gd
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
WORKDIR /var/www
COPY . /var/www
RUN composer install --no-dev --optimize-autoloader
RUN chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache
EXPOSE 8080
CMD php artisan serve --host=0.0.0.0 --port=8080
