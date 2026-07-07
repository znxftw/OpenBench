#!/bin/bash
set -e

# Wait for MySQL database to become ready
echo "Checking database connection..."
until nc -z -v -w3 "$DB_HOST" "$DB_PORT"; do
  echo "Waiting for MySQL database at $DB_HOST:$DB_PORT..."
  sleep 2
done
echo "MySQL is up and running!"

# If requirements.txt exists in the mounted volume, install any changes
if [ -f "/app/requirements.txt" ]; then
  echo "Installing dependencies from requirements.txt..."
  pip install --no-cache-dir -r /app/requirements.txt
fi

# Run Django migrations
echo "Running database migrations..."
python manage.py migrate
python manage.py migrate --run-syncdb

# Collect static files
echo "Collecting static files..."
python manage.py collectstatic --no-input

# Seed the superuser and the worker user non-interactively using python shell
echo "Setting up initial users..."
python manage.py shell <<EOF
import os
import django
django.setup()
from django.contrib.auth.models import User
from OpenBench.models import Profile

# 1. Setup Django Superuser (for Admin panel access)
su_username = os.environ.get('DJANGO_SUPERUSER_USERNAME', 'admin')
su_email = os.environ.get('DJANGO_SUPERUSER_EMAIL', 'admin@example.com')
su_password = os.environ.get('DJANGO_SUPERUSER_PASSWORD', 'adminpassword')

if not User.objects.filter(username=su_username).exists():
    User.objects.create_superuser(su_username, su_email, su_password)
    # Give superuser staff and superuser permissions on profile
    u = User.objects.get(username=su_username)
    p, _ = Profile.objects.get_or_create(user=u)
    p.enabled = True
    p.approver = True
    p.save()
    print(f"Django superuser '{su_username}' created and enabled.")
else:
    print(f"Django superuser '{su_username}' already exists.")

# 2. Setup Worker User (so client can connect out of the box)
worker_username = os.environ.get('WORKER_USER', 'homelab_worker')
worker_password = os.environ.get('WORKER_PASSWORD', 'worker_secret_password')

if worker_username:
    if not User.objects.filter(username=worker_username).exists():
        u = User.objects.create_user(worker_username, password=worker_password)
        p, _ = Profile.objects.get_or_create(user=u)
        p.enabled = True
        p.approver = True
        p.save()
        print(f"Worker user '{worker_username}' created, activated, and enabled as an approver.")
    else:
        u = User.objects.get(username=worker_username)
        # Ensure password matches what is in env if they want to override
        u.set_password(worker_password)
        u.save()
        p, _ = Profile.objects.get_or_create(user=u)
        p.enabled = True
        p.approver = True
        p.save()
        print(f"Worker user '{worker_username}' password updated and verified.")
EOF

echo "Starting OpenBench web server under Gunicorn..."
# Use exec to ensure signals (like SIGTERM) are forwarded properly to Gunicorn for graceful shutdown
exec gunicorn OpenSite.wsgi:application --bind 0.0.0.0:8000 --workers 3
