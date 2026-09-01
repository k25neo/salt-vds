install_base_packages:
  pkg.installed:
    - names:
      - curl
      - git
      - tmux
      - htop

create_hello_file:
  file.managed:
    - name: /root/hello_from_windows.txt
    - contents: "Этот файл создался из папки states на Windows!"