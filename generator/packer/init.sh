#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get -yq update
apt-get -yq upgrade
apt-get -yq install chrony
id -u stressgrid &>/dev/null || useradd -r stressgrid
mkdir -p /opt/stressgrid/generator
chown stressgrid:stressgrid /opt/stressgrid/generator
cd /opt/stressgrid/generator
sudo -u stressgrid tar -xvf /tmp/generator.tar.gz &>/dev/null
rm /tmp/generator.tar.gz
echo "
net.ipv4.ip_local_port_range=15000 65000
" > /etc/sysctl.d/10-stressgrid-generator.conf
sysctl -p /etc/sysctl.d/10-stressgrid-generator.conf
echo "[Unit]
Description=Stressgrid Generator
After=network.target

[Service]
WorkingDirectory=/opt/stressgrid/generator
Environment=HOME=/opt/stressgrid/generator
EnvironmentFile=/etc/default/stressgrid-generator.env
ExecStart=/opt/stressgrid/generator/bin/generator start
ExecStop=/opt/stressgrid/generator/bin/generator stop
User=stressgrid
RemainAfterExit=yes
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/stressgrid-generator.service
echo "" > /etc/default/stressgrid-generator.env
systemctl daemon-reload
systemctl enable stressgrid-generator
