# Гарантируем, что базовый пакет ocserv установлен
install_ocserv_packages:
  pkg.installed:
    - name: ocserv

# Создаем конфигурационный файл RADIUS-клиента для самого ocserv (БЕЗ КОММЕНТАРИЕВ В СТРОКЕ!)
configure_ocserv_radius_client:
  file.managed:
    - name: /etc/radcli/radiusclient.conf
    - makedirs: True
    - contents: |
        nas-identifier  ocserv
        authserver      127.0.0.1:1812
        acctserver      127.0.0.1:1813
        servers         /etc/radcli/servers
        dictionary      /etc/freeradius/3.0/dictionary
        radius_timeout  5
        radius_retries  3
    - require:
      - pkg: install_ocserv_packages

# Прописываем секретный ключ RADIUS в файл серверов radcli
configure_ocserv_radius_servers_key:
  file.managed:
    - name: /etc/radcli/servers
    - contents: |
        127.0.0.1       {{ salt['pillar.get']('secrets:radius_shared_secret') }}
    - mode: '0600'
    - user: root
    - group: root
    - require:
      - file: configure_ocserv_radius_client

# Настраиваем главный конфигурационный файл ocserv
configure_ocserv_main:
  file.managed:
    - name: /etc/ocserv/ocserv.conf
    - contents: |
        # Прямая авторизация через RADIUS в обход PAM
        auth = "radius[config=/etc/radcli/radiusclient.conf]"
        acct = "radius[config=/etc/radcli/radiusclient.conf]"
        
        # Системные параметры Debian 12
        socket-file = /run/ocserv.socket
        chroot-dir = /var/lib/ocserv
        
        # Порты для подключения клиентов
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

# Включаем форвардинг пакетов на уровне ядра Linux
enable_ip_forwarding:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1

# Устанавливаем утилиту iptables и инструмент сохранения правил при перезагрузке
install_iptables_packages:
  pkg.installed:
    - names:
      - iptables
      - iptables-persistent

# Автоматически настраиваем маскарадинг (NAT) для трафика из подсети VPN
enable_vpn_nat:
  cmd.run:
    - name: iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o $(ip route show default | awk '{print $5}') -j MASQUERADE
    - unless: iptables -t nat -C POSTROUTING -s 192.168.10.0/24 -j MASQUERADE
    - require:
      - pkg: install_iptables_packages

# Сохраняем правила в системный файл, чтобы они автоматически поднимались после ребута сервера
save_iptables_rules:
  cmd.run:
    - name: iptables-save > /etc/iptables/rules.v4
    - watch:
      - cmd: enable_vpn_nat

# Перезапускаем OpenConnect, если его конфиги изменились
restart_services_ocserv:
  service.running:
    - name: ocserv
    - enable: True
    - watch:
      - file: configure_ocserv_main
      - file: configure_ocserv_radius_client
      - file: configure_ocserv_radius_servers_key
