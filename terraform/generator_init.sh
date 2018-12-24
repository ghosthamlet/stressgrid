#!/bin/bash
echo "COORDINATOR_URL=ws://${coordinator_dns}:9696" > /etc/default/stressgrid-generator.env
service stressgrid-generator restart