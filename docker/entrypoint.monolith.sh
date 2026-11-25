#!/bin/bash
set -e

PORT=${PORT:-8080}

echo "=== Iniciando TELCOM 2.0 (Contenedor Único) en puerto $PORT ==="

mkdir -p storage/framework/sessions storage/framework/views storage/framework/cache storage/logs bootstrap/cache /run/nginx
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
fi

if [ -z "$APP_KEY" ]; then
    echo "Configurando APP_KEY..."
    php artisan key:generate --force || true
fi

php artisan storage:link --quiet || true

# Esperar a PostgreSQL si está configurado
if [ -n "$DB_HOST" ]; then
    echo "Verificando conexión PostgreSQL en $DB_HOST:${DB_PORT:-5432}..."
    max_retries=30
    count=0
    until php -r "try { new PDO('pgsql:host='.getenv('DB_HOST').';port='.(getenv('DB_PORT')?:'5432').';dbname='.getenv('DB_DATABASE'), getenv('DB_USERNAME'), getenv('DB_PASSWORD')); exit(0); } catch (Throwable \$e) { exit(1); }" 2>/dev/null; do
        count=$((count+1))
        if [ $count -ge $max_retries ]; then
            echo "Aviso: No se pudo conectar a PostgreSQL tras $max_retries intentos. Continuando..."
            break
        fi
        sleep 1
    done
fi

if [ "$RUN_MIGRATIONS" = "true" ]; then
    echo "Ejecutando migraciones..."
    php artisan migrate --force || echo "Aviso: Error durante las migraciones."
fi

if [ "$RUN_SEEDERS" = "true" ]; then
    echo "Ejecutando seeders..."
    php artisan db:seed --force || echo "Aviso: Seeders omitidos o ya aplicados."
fi

php artisan config:clear || true
php artisan route:clear || true
php artisan view:clear || true

if [ "$APP_ENV" = "production" ]; then
    php artisan config:cache || true
    php artisan route:cache || true
    php artisan view:cache || true
fi

# Configurar puerto dinámico de Render en Nginx
sed "s/__PORT__/$PORT/g" /etc/nginx/http.d/default.conf.template > /etc/nginx/http.d/default.conf

# Iniciar backend Laravel interno en segundo plano
php -S 127.0.0.1:8000 -t /app/public /app/public/index.php &

echo "=== Nginx + Laravel listos en puerto $PORT ==="
exec nginx -g "daemon off;"
