Create userparam keepalived.vrrp.discovery
```
sudo tee /etc/zabbix/zabbix_agent2.d/keepalived.conf << 'EOF'
UserParameter=keepalived.vrrp.discovery,sudo /etc/zabbix/keepalived_discovery.sh
EOF
```

Add keepalived_discovery.sh in /etc/zabbix/
```
chmod +x /etc/zabbix/keepalived_discovery.sh
```
Allow the zabbix user to run the script via sudo without a password prompt
sudo visudo -f /etc/sudoers.d/zabbix
```
zabbix ALL=(ALL) NOPASSWD: /etc/zabbix/keepalived_discovery.sh
```
Restart the agent to apply changes:
```
sudo systemctl restart zabbix-agent
```
or
```
sudo systemctl restart zabbix-agent2
```
