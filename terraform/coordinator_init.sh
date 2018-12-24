#!/bin/bash
echo "CW_REGION=${region}" > /etc/default/stressgrid-coordinator.env
service stressgrid-coordinator restart