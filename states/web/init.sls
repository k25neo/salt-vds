install_nginx:
  pkg.installed:
    - name: nginx

ensure_nginx_running:
  service.running:
    - name: nginx
    - enable: True
    - require:
      - pkg: install_nginx
