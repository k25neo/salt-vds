# salt-vds

ssh-keygen -t rsa -b 4096 

ssh-copy-id root@213.155.10.188 
или 
cat C:\Users\$env:USERNAME\.ssh\id_rsa.pub | ssh root@213.155.10.188 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"

docker compose up -d --build
docker compose exec salt-master sh

salt-ssh 'vds-host' state.highstate