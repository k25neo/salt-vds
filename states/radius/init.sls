# Устанавливаем FreeRADIUS и плагин для работы с MySQL/MariaDB
install_radius_packages:
  pkg.installed:
    - names:
      - freeradius
      - freeradius-mysql
      - freeradius-utils

# Гарантируем, что служба запущена
ensure_radius_running:
  service.running:
    - name: freeradius
    - enable: True
    - require:
      - pkg: install_radius_packages

# Импортируем стандартную схему таблиц RADIUS в базу данных, если таблиц там еще нет
import_radius_sql_schema:
  cmd.run:
    - name: mariadb radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
    - unless: mariadb radius -e "EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='radius' AND table_name='radcheck');"
    - require:
      - pkg: install_radius_packages

# 1. Настраиваем подключение к MySQL в модуле sql
configure_radius_sql_module:
  file.replace:
    - name: /etc/freeradius/3.0/mods-available/sql
    - pattern: '^\s*dialect\s*=\s*.*$'
    - repl: '  dialect = "mysql"'
    - require:
      - pkg: install_radius_packages

configure_radius_sql_db:
  file.replace:
    - name: /etc/freeradius/3.0/mods-available/sql
    - pattern: '^\s*database\s*=\s*.*$'
    - repl: '  database = "radius"'
    - require:
      - pkg: install_radius_packages

configure_radius_sql_password:
  file.replace:
    - name: /etc/freeradius/3.0/mods-available/sql
    - pattern: '^\s*password\s*=\s*.*$'
    - repl: "  password = '{{ salt['pillar.get']('secrets:mysql_radius_password') }}'"
    - require:
      - pkg: install_radius_packages

# 2. Включаем SQL-модуль (создаем символическую ссылку в mods-enabled)
enable_radius_sql_module:
  file.symlink:
    - name: /etc/freeradius/3.0/mods-enabled/sql
    - target: /etc/freeradius/3.0/mods-available/sql
    - require:
      - file: configure_radius_sql_password

# 3. Включаем чтение SQL в профиле 'default'
enable_sql_in_default_site:
  file.replace:
    - name: /etc/freeradius/3.0/sites-available/default
    - pattern: '^\s*#\s*-sql'
    - repl: '	-sql'
    - require:
      - pkg: install_radius_packages

# 4. Включаем чтение SQL в профиле 'inner-tunnel'
enable_sql_in_inner_tunnel_site:
  file.replace:
    - name: /etc/freeradius/3.0/sites-available/inner-tunnel
    - pattern: '^\s*#\s*-sql'
    - repl: '	-sql'
    - require:
      - pkg: install_radius_packages

# 5. Перезапускаем FreeRADIUS, если конфиги изменились
restart_radius_on_conf_change:
  service.running:
    - name: freeradius
    - watch:
      - file: configure_radius_sql_password
      - file: enable_radius_sql_module
      - file: enable_sql_in_default_site
      - file: enable_sql_in_inner_tunnel_site
