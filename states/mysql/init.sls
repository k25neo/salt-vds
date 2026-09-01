# Устанавливаем сервер MariaDB и клиентскую библиотеку для Salt
install_mysql_packages:
  pkg.installed:
    - names:
      - mariadb-server
      - python3-pymysql

# Гарантируем, что служба базы данных запущена и в автозагрузке
ensure_mysql_running:
  service.running:
    - name: mariadb
    - enable: True
    - require:
      - pkg: install_mysql_packages

# Создаем базу данных для FreeRADIUS, принудительно используя дефолтный сокет из-под root системы
create_radius_db:
  mysql_database.present:
    - name: radius
    - connection_user: root
    - connection_unix_socket: /run/mysqld/mysqld.sock  # <-- Заставляем использовать системный UNIX-сокет (пароль не нужен!)
    - require:
      - service: ensure_mysql_running

# Создаем пользователя для FreeRADIUS
create_radius_user:
  mysql_user.present:
    - name: radius
    - host: localhost
    - password: "{{ salt['pillar.get']('secrets:mysql_radius_password') }}"
    - connection_user: root
    - connection_unix_socket: /run/mysqld/mysqld.sock  # <-- Используем тот же сокет
    - require:
      - mysql_database: create_radius_db

# Даем пользователю права на его базу данных
grant_radius_privileges:
  mysql_grants.present:
    - grant: all privileges
    - database: radius.*
    - user: radius
    - host: localhost
    - connection_user: root
    - connection_unix_socket: /run/mysqld/mysqld.sock  # <-- Используем тот же сокет
    - require:
      - mysql_user: create_radius_user
