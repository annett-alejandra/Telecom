# =========================================================================
# Dockerfile Monolítico (Frontend + Backend en un solo contenedor para Render)
# =========================================================================

# Etapa 1: Compilar Frontend React + Vite
FROM node:20-alpine AS frontend-build
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci || npm install
COPY frontend/ ./
ARG VITE_API_URL=/api
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

# Etapa 2: Backend Laravel + Nginx sirviendo SPA + Proxy /api/
FROM php:8.3-cli-alpine

RUN apk add --no-cache \
    nginx \
    postgresql-dev \
    libzip-dev \
    zip \
    unzip \
    git \
    bash \
    curl \
    && docker-php-ext-install pdo pdo_pgsql pdo_mysql bcmath opcache zip

COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Dependencias PHP
COPY backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

# Código del backend
COPY backend/ ./
RUN composer dump-autoload --optimize --no-dev

# Permisos de Laravel
RUN mkdir -p storage/framework/sessions storage/framework/views storage/framework/cache storage/logs bootstrap/cache \
    && chown -R www-data:www-data /app/storage /app/bootstrap/cache \
    && chmod -R 775 /app/storage /app/bootstrap/cache

# Assets compilados del frontend
COPY --from=frontend-build /frontend/dist /var/www/html

# Configuración Nginx y script de arranque
COPY docker/nginx.monolith.conf /etc/nginx/http.d/default.conf.template
COPY docker/entrypoint.monolith.sh /usr/local/bin/entrypoint.monolith.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.monolith.sh \
    && chmod +x /usr/local/bin/entrypoint.monolith.sh \
    && mkdir -p /run/nginx

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.monolith.sh"]
