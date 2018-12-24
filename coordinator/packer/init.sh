#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get -yq update
apt-get -yq upgrade
apt-get -yq install chrony
id -u stressgrid &>/dev/null || useradd -r stressgrid
mkdir -p /opt/stressgrid/coordinator
chown stressgrid:stressgrid /opt/stressgrid/coordinator
cd /opt/stressgrid/coordinator
sudo -u stressgrid tar -xvf /tmp/coordinator.tar.gz &>/dev/null
rm /tmp/coordinator.tar.gz
echo "[Unit]
Description=Stressgrid Coordinator
After=network.target

[Service]
WorkingDirectory=/opt/stressgrid/coordinator
Environment=HOME=/opt/stressgrid/coordinator
EnvironmentFile=/etc/default/stressgrid-coordinator.env
ExecStart=/opt/stressgrid/coordinator/bin/coordinator start
ExecStop=/opt/stressgrid/coordinator/bin/coordinator stop
User=stressgrid
RemainAfterExit=yes
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/stressgrid-coordinator.service
echo "" > /etc/default/stressgrid-coordinator.env
systemctl daemon-reload
systemctl enable stressgrid-coordinator
