# Устанавливаем OpenConnect Server и модуль интеграции PAM с RADIUS
install_ocserv_packages:
  pkg.installed:
    - names:
      - ocserv
      - libpam-radius-auth

# Настраиваем RADIUS-клиент для PAM, прописывая туда наш секретный ключ из Pillar
configure_pam_radius_server:
  file.managed:
    - name: /etc/pam_radius_auth.conf
    - contents: |
        # server[:port] secret [timeout] [hint]
        127.0.0.1       {{ salt['pillar.get']('secrets:radius_shared_secret') }} 5
    - mode: '0600'
    - user: root
    - group: root
    - require:
      - pkg: install_ocserv_packages

# Прописываем этот же секретный ключ в локальный FreeRADIUS, чтобы он принимал запросы от самого себя
configure_freeradius_local_client:
  file.managed:
    - name: /etc/freeradius/3.0/clients.d/localhost.conf
    - makedirs: True
    - contents: |
        client localhost_pam {
            ipaddr = 127.0.0.1
            secret = {{ salt['pillar.get']('secrets:radius_shared_secret') }}
        }
    - require:
      - pkg: install_ocserv_packages

# Настраиваем PAM-профиль для ocserv, чтобы он использовал только RADIUS для проверки паролей
configure_ocserv_pam_auth:
  file.managed:
    - name: /etc/pam.d/ocserv
    - contents: |
        auth      required  pam_radius_auth.so
        account   required  pam_permit.so
    - require:
      - pkg: install_ocserv_packages

# Настраиваем главный конфигурационный файл ocserv
configure_ocserv_main:
  file.managed:
    - name: /etc/ocserv/ocserv.conf
    - contents: |
        # Авторизация через PAM (который смотрит в RADIUS)
        auth = "pam[gid-min=1000]"
        
        # Перевели на порт 4443, так как порт 443 занят сервером Nginx!
        tcp-port = 4443
        udp-port = 4443
        
        run-as-user = ocserv
        run-as-group = ocserv
        
        # Настройка виртуальной сети для VPN-клиентов
        device = vpns
        ipv4-network = 192.168.10.0
        ipv4-netmask = 255.255.255.0
        dns = 8.8.8.8
        dns = 1.1.1.1
        
        # Ссылки на ваши выпущенные сертификаты Let's Encrypt
        server-cert = /etc/letsencrypt/live/printlab3d.ru/fullchain.pem
        server-key = /etc/letsencrypt/live/printlab3d.ru/privkey.pem
        
        # Маршрутизация (направлять весь трафик в VPN)
        route = default
        
        keepalive = 32400
        dpd = 90
        mobile-dpd = 1800
        tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT"
        auth-timeout = 240
        max-clients = 128
        max-same-clients = 5
        cisco-client-compat = true
        dtls-legacy = true
    - require:
      - pkg: install_ocserv_packages

# ИСПРАВИЛИ: Включаем форвардинг пакетов на уровне ядра Linux (правильный синтаксис Salt)
enable_ip_forwarding:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1

# Перезапускаем сервисы, чтобы применить все изменения
restart_services_ocserv:
  service.running:
    - name: ocserv
    - enable: True
    - watch:
      - file: configure_ocserv_main
      - file: configure_ocserv_pam_auth

restart_services_radius_ocserv:
  service.running:
    - name: freeradius
    - watch:
      - file: configure_freeradius_local_client
