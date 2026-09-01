# Устанавливаем Certbot и плагин интеграции с Nginx
install_certbot:
  pkg.installed:
    - names:
      - certbot
      - python3-certbot-nginx

# Автоматически выпускаем сертификат (если его еще нет)
# Внимание: укажите ваш реальный email для уведомлений от Let's Encrypt
request_ssl_certificate:
  cmd.run:
    # Подставляем email из пиллара динамически
    - name: certbot --nginx -d printlab3d.ru -d www.printlab3d.ru --non-interactive --agree-tos -m {{ salt['pillar.get']('secrets:letsencrypt_email') }} --keep-until-expiring
    - require:
      - pkg: install_certbot
      - service: ensure_nginx_running
