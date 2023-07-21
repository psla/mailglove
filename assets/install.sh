#!/bin/bash

#supervisor.conf already exists? do not reinstall!
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

#supervisor
cat >> /etc/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:postfix]
command=/opt/postfix.sh

[program:rsyslog]
command=/usr/sbin/rsyslogd -n
EOF

############
#  postfix
############
cat >> /opt/postfix.sh <<EOF
#!/bin/sh
/usr/sbin/postfix start
tail -f /var/log/mail.log
EOF
chmod +x /opt/postfix.sh
postconf -e myhostname=${DOMAIN}
postconf -F '*/*/chroot = n'

# Add the myhook hook to the end of master.cf
tee -a /etc/postfix/master.cf <<'EOF'
myhook unix - n n - - pipe
    flags=F user=nobody argv=/opt/webhook.js ${recipient} ${sender} ${size}
EOF

echo "TLS enabled: ${TLS}"

if [ "$TLS" == "true" ]
then
echo "Enabling TLS"
tee -a /etc/postfix/main.cf <<'EOF'
smtpd_tls_cert_file=/etc/postfix/ssl/server.csr
smtpd_tls_key_file=/etc/postfix/ssl/server.key
smtpd_tls_security_level=may
EOF
fi

# https://serverfault.com/questions/258469/how-to-configure-postfix-to-pipe-all-incoming-email-to-a-script
tee -a /etc/postfix/virtual_aliases <<EOF
@$DOMAIN    allmail@apimail.budget.usa.sepio.pl
EOF

tee -a /etc/postfix/transport <<EOF
$DOMAIN    myhook:
EOF

postmap /etc/postfix/virtual_aliases
postmap /etc/postfix/transport

# 
# virtual_alias_maps = lmdb:/etc/postfix/virtual_aliases
# transport_maps = lmdb:/etc/postfix/transport
postconf 'transport_maps = lmdb:/etc/postfix/transport'
postconf 'virtual_alias_maps = lmdb:/etc/postfix/virtual_aliases'

# Disable bounces
postconf -F 'bounce/unix/command = discard'

# Disable local recipient maps so nothing is dropped b/c of non-existent email
postconf 'local_recipient_maps ='

# Make the webhook.js use the correct URI
sed -i "s/__URL__/${URL//\//\\/}/" /opt/webhook.js

#############
## Enable TLS
#############
#if [[ -n "$(find /etc/postfix/certs -iname *.crt)" && -n "$(find /etc/postfix/certs -iname *.key)" ]]; then
#  # /etc/postfix/main.cf
#  postconf -e smtpd_tls_cert_file=$(find /etc/postfix/certs -iname *.crt)
#  postconf -e smtpd_tls_key_file=$(find /etc/postfix/certs -iname *.key)
#  chmod 400 /etc/postfix/certs/*.*
#  # /etc/postfix/master.cf
#  postconf -M submission/inet="submission   inet   n   -   n   -   -   smtpd"
#  postconf -P "submission/inet/syslog_name=postfix/submission"
#  postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
#  postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
#  postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
#  postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination"
#fi
