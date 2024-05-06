include globals.local

ignore noroot
ignore nogroups
#private-etc fonts,@tls-ca,@x11,host.conf,mime.types,rpc,services
ignore private-etc

noblacklist ${RUNUSER}

include nodejs-common.profile

