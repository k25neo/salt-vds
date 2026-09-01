# Устанавливаем FreeRADIUS и плагин для работы с MySQL/MariaDB
install_radius_packages:
  pkg.installed:
    - names:
      - freeradius
      - freeradius-mysql
      - freeradius-utils

# Импортируем стандартную схему таблиц RADIUS в базу данных, если таблиц там еще нет
import_radius_sql_schema:
  cmd.run:
    - name: mariadb radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
    - unless: mariadb radius -e "EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='radius' AND table_name='radcheck');"
    - require:
      - pkg: install_radius_packages

# 1. ЧИСТОЕ УПРАВЛЕНИЕ МОДУЛЕМ SQL (Без ломающихся регулярных выражений, подключение по TCP 3306)
configure_radius_sql_module_file:
  file.managed:
    - name: /etc/freeradius/3.0/mods-available/sql
    - contents: |
        sql {
            dialect = "mysql"
            driver = "rlm_sql_mysql"
            
            # Настройки подключения по сети TCP (как в Ansible)
            server = "localhost"
            port = 3306
            login = "radius"
            password = "{{ salt['pillar.get']('secrets:mysql_radius_password') }}"
            radius_db = "radius"
            
            # Отключаем TLS полностью, чтобы не требовал сертификаты
            mysql {
                tls {
                    tls_required = no
                }
            }
            
            # Стандартная карта таблиц FreeRADIUS
            acct_table1 = "radacct"
            acct_table2 = "radacct"
            postauth_table = "radpostauth"
            authcheck_table = "radcheck"
            groupcheck_table = "radgroupcheck"
            authreply_table = "radreply"
            groupreply_table = "radgroupreply"
            usergroup_table = "radusergroup"
        }
    - require:
      - pkg: install_radius_packages

# 2. ЧИСТОЕ УПРАВЛЕНИЕ МОДУЛЕМ PAP (Включаем auto_header и метод crypt для SHA-512)
configure_radius_pap_module_file:
  file.managed:
    - name: /etc/freeradius/3.0/mods-available/pap
    - contents: |
        pap {
            auto_header = yes
            crypt = "crypt"
        }
    - require:
      - pkg: install_radius_packages

# Включаем символические ссылки для модулей sql и mschap
enable_radius_sql_link:
  file.symlink:
    - name: /etc/freeradius/3.0/mods-enabled/sql
    - target: /etc/freeradius/3.0/mods-available/sql
    - require:
      - file: configure_radius_sql_module_file

enable_radius_mschap_link:
  file.symlink:
    - name: /etc/freeradius/3.0/mods-enabled/mschap
    - target: /etc/freeradius/3.0/mods-available/mschap
    - require:
      - pkg: install_radius_packages

# 3. Перезаписываем профиль 'default' (С явным вызовом sql и pap)
configure_default_site_clean:
  file.managed:
    - name: /etc/freeradius/3.0/sites-available/default
    - contents: |
        server default {
            listen {
                type = auth
                ipaddr = *
                port = 1812
            }
            listen {
                type = acct
                ipaddr = *
                port = 1813
            }
            authorize {
                filter_username
                preprocess
                chap
                mschap
                digest
                sql
                eap
                pap
            }
            authenticate {
                Auth-Type PAP {
                    pap
                }
                Auth-Type CHAP {
                    chap
                }
                Auth-Type MS-CHAP {
                    mschap
                }
                Auth-Type EAP {
                    eap
                }
            }
            accounting {
                sql
            }
            post-auth {
                sql
                Post-Auth-Type REJECT {
                    sql
                }
            }
        }
    - require:
      - pkg: install_radius_packages

# 4. Перезаписываем профиль 'inner-tunnel'
configure_inner_tunnel_site_clean:
  file.managed:
    - name: /etc/freeradius/3.0/sites-available/inner-tunnel
    - contents: |
        server inner-tunnel {
            authorize {
                preprocess
                chap
                mschap
                sql
                eap
                pap
            }
            authenticate {
                Auth-Type PAP {
                    pap
                }
                Auth-Type CHAP {
                    chap
                }
                Auth-Type MS-CHAP {
                    mschap
                }
                Auth-Type EAP {
                    eap
                }
            }
            accounting {
                sql
            }
            post-auth {
                sql
                Post-Auth-Type REJECT {
                    sql
                }
            }
        }
    - require:
      - pkg: install_radius_packages

# 5. Разрешаем FreeRADIUS принимать запросы с любых IP-адресов этого сервера с общим ключом
fix_freeradius_universal_client:
  file.append:
    - name: /etc/freeradius/3.0/clients.conf
    - text: |
        client vds_local_network {
            ipaddr = 0.0.0.0/0
            secret = {{ salt['pillar.get']('secrets:radius_shared_secret') }}
        }
    - require:
      - pkg: install_radius_packages

# 6. Отключаем дефолтный капризный systemd-сервис
disable_broken_systemd_service:
  service.dead:
    - name: freeradius
    - enable: False
    - require:
      - pkg: install_radius_packages

# Принудительно убиваем старые процессы и перезапускаем фонового демона при ЛЮБОМ изменении конфигов
kill_stale_radius_processes:
  cmd.run:
    - name: killall freeradius || true
    - watch:
      - file: configure_radius_sql_module_file
      - file: configure_radius_pap_module_file
      - file: enable_radius_sql_link
      - file: enable_radius_mschap_link
      - file: configure_default_site_clean
      - file: configure_inner_tunnel_site_clean
      - file: fix_freeradius_universal_client

# Запускаем FreeRADIUS напрямую в фоновом режиме
start_freeradius_daemon_directly:
  cmd.run:
    - name: /usr/sbin/freeradius -d /etc/freeradius/3.0 -f > /var/log/freeradius/console.log 2>&1 &
    - unless: ss -uulpn | grep -q :1812
    - require:
      - service: disable_broken_systemd_service
