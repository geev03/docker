#!/bin/bash

if [[ -z "${SUPERVISOR_PASSWD}" ]]; then
  _PASSWORD="$RANDOM.$RANDOM"
  # echo >&2 ":: Supervisor web console: admin's password is $_PASSWORD"
else
  _PASSWORD="${SUPERVISOR_PASSWD}"
fi

_LOG_LEVEL="${SUPERVISOR_LOG_LEVEL:-info}"

########################################################################
# The configuration generator
########################################################################

cat \
  > /etc/supervisord.conf \
<<EOF
;
; supervisord main config file - v0.1
; Do not edit this file
;

[unix_http_server]
file=/var/run/supervisor.sock   ; (the path to the socket file)
chmod=0700                      ; sockef file mode (default 0700)

;[inet_http_server]
;port=127.0.0.1:9001
;username=admin
;password=${_PASSWORD}

[supervisord]
nodaemon=true
logfile=/supervisor/__daemon.log ; (main log file;default $CWD/supervisord.log)
pidfile=/var/run/supervisord.pid ; (supervisord pidfile;default supervisord.pid)
childlogdir=/supervisor/         ; ('AUTO' child log dir, default $TEMP)
logfile_maxbytes=50MB            ; (max main logfile bytes b4 rotation;default 50MB)
logfile_backups=10               ; (num of main logfile rotation backups;default 10)
loglevel=$_LOG_LEVEL             ; (log level;default info; others: debug,warn,trace)

; the below section must remain in the config file for RPC
; (supervisorctl/web interface) to work, additional interfaces may be
; added by defining them in separate rpcinterface: sections
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock ; use a unix:// URL  for a unix socket

[include]
files = /etc/s.supervisor/*.s
EOF

########################################################################
# Execute all generators!!!
########################################################################

while read FILE; do
  chmod -c 755 "$FILE" # FIXME: This is a Docker bug!
  bash -n "$FILE" \
  && {
    echo >&2 ":: Executing generator '$FILE'..."
    bash "$FILE"
  } \
  || true
done \
< <(find /etc/s.supervisor/ -type f -iname "*.sh")

########################################################################
# uid/gid fixing
########################################################################

env \
| grep -E '^[A-Z0-9]+_UID=[0-9]+$' \
| awk -F '_UID=' '{
    name = tolower($1);
    id = $2;
    if (id == 0) { id = 6000; }
    printf("usermod -u %s -g %s %s || useradd -u %s -g %s %s\n", id, id, name, id, id, name);
  }' \
| bash

env \
| grep -E '^[A-Z0-9]+_GID=[0-9]+$' \
| awk -F '_GID=' '{
    name = tolower($1);
    id = $2;
    if (id == 0) { id = 6000; }
    printf("groupmod -g %s %s || groupadd -g %s %s\n", id, name, id, name);
  }' \
| bash

exec /usr/bin/supervisord --configuration /etc/supervisord.conf
