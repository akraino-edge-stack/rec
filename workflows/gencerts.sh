#!/bin/bash
#
#  Script to create self-signed certificates in directory $1.
#

cd $1

cat > openssl-ca.cnf << EOF
HOME            = .
RANDFILE        = \$ENV::HOME/.rnd

####################################################################
[ ca ]
default_ca    = CA_default      # The default ca section

[ CA_default ]

dir               = /root/ca
default_days     = 1000         # How long to certify for
default_crl_days = 30           # How long before next CRL
default_md       = sha256       # Use public key default MD
preserve         = no           # Keep passed DN ordering

x509_extensions = ca_extensions # The extensions to add to the cert

email_in_dn     = no            # Don't concat the email in the DN
copy_extensions = copy          # Required to copy SANs from CSR to cert

####################################################################
[ req ]
prompt = no
default_bits       = 4096
default_keyfile    = cakey.pem
distinguished_name = ca_distinguished_name
x509_extensions    = ca_extensions
string_mask        = utf8only

####################################################################
[ ca_distinguished_name ]
countryName           = FI
organizationName      = Nokia OY
# commonName          = Nokia
# commonName_default  = Test Server
# emailAddress        = test@server.com
stateOrProvinceName   = Uusimaa
localityName          = Espoo

####################################################################
[ ca_extensions ]

subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints       = critical, CA:true
keyUsage               = keyCertSign, cRLSign
EOF

cat > openssl-server.cnf << EOF
HOME            = .
RANDFILE        = \$ENV::HOME/.rnd

####################################################################
[ req ]
prompt	= no
default_bits       = 2048
default_keyfile    = serverkey.pem
distinguished_name = server_distinguished_name
req_extensions     = server_req_extensions
string_mask        = utf8only

####################################################################
[ server_distinguished_name ]
countryName           = FI
organizationName      = Nokia NET
commonName            = Test Server
# emailAddress        = test@server.com
stateOrProvinceName   = Uusimaa
localityName          = Espoo

####################################################################
[ server_req_extensions ]

subjectKeyIdentifier = hash
basicConstraints     = CA:FALSE
keyUsage             = digitalSignature, keyEncipherment
subjectAltName       = @alternate_names
nsComment            = "OpenSSL Generated Certificate"

####################################################################
[ alternate_names ]

DNS.1  = server.com
EOF

cat > openssl-client.cnf << EOF
HOME            = .
RANDFILE        = \$ENV::HOME/.rnd

####################################################################
[ req ]
prompt = no
default_bits       = 2048
default_keyfile    = clientkey.pem
distinguished_name = client_distinguished_name
req_extensions     = client_req_extensions
string_mask        = utf8only

####################################################################
[ client_distinguished_name ]
countryName          = DE
organizationName     = Customer X
commonName           = Customer
emailAddress         = test@client.com

####################################################################
[ client_req_extensions ]

subjectKeyIdentifier = hash
basicConstraints     = CA:FALSE
keyUsage             = digitalSignature, keyEncipherment
subjectAltName       = @alternate_names
nsComment            = "OpenSSL Generated Certificate"

####################################################################
[ alternate_names ]

DNS.1  = ramuller.zoo.dynamic.nsn-net.net
DNS.2  = www.client.com
DNS.3  = mail.client.com
DNS.4  = ftp.client.com
EOF

cat > openssl-ca-sign.cnf << EOF
HOME            = .
RANDFILE        = \$ENV::HOME/.rnd

####################################################################
[ ca ]
default_ca    = CA_default      # The default ca section

[ CA_default ]

default_days     = 1000         # How long to certify for
default_crl_days = 30           # How long before next CRL
default_md       = sha256       # Use public key default MD
preserve         = no           # Keep passed DN ordering

x509_extensions = ca_extensions # The extensions to add to the cert

email_in_dn     = no            # Don't concat the email in the DN
copy_extensions = copy          # Required to copy SANs from CSR to cert
base_dir      = .
certificate   = \$base_dir/cacert.pem   # The CA certifcate
private_key   = \$base_dir/cakey.pem    # The CA private key
new_certs_dir = \$base_dir              # Location for new certs after signing
database      = \$base_dir/index.txt    # Database index file
serial        = \$base_dir/serial.txt   # The current serial number

unique_subject = no  # Set to 'no' to allow creation of
                     # several certificates with same subject.

####################################################################
[ req ]
prompt = no
default_bits       = 4096
default_keyfile    = cakey.pem
distinguished_name = ca_distinguished_name
x509_extensions    = ca_extensions
string_mask        = utf8only

####################################################################
[ ca_distinguished_name ]
countryName           = FI
organizationName      = Nokia OY
# commonName          = Nokia
# commonName_default  = Test Server
# emailAddress        = test@server.com
stateOrProvinceName   = Uusimaa
localityName          = Espoo

####################################################################
[ ca_extensions ]

subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints       = critical, CA:true
keyUsage               = keyCertSign, cRLSign

####################################################################
[ signing_policy ]
countryName            = optional
stateOrProvinceName    = optional
localityName           = optional
organizationName       = optional
organizationalUnitName = optional
commonName             = supplied
emailAddress           = optional

####################################################################
[ signing_req ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
EOF

openssl req -config openssl-ca.cnf -x509 -newkey rsa:2048 -sha256 -nodes -out cacert.pem     -outform PEM
openssl req -config openssl-server.cnf   -newkey rsa:2048 -sha256 -nodes -out servercert.csr -outform PEM 
openssl req -config openssl-client.cnf   -newkey rsa:2048 -sha256 -nodes -out clientcert.csr -outform PEM
echo -n   > index.txt
echo '01' > serial.txt
echo -n   > index-ri.txt
echo '01' > serial-ri.txt
echo -e "y\ny\n" | openssl ca -config openssl-ca-sign.cnf -policy signing_policy -extensions signing_req -out servercert.pem -infiles servercert.csr
echo -e "y\ny\n" | openssl ca -config openssl-ca-sign.cnf -policy signing_policy -extensions signing_req -out clientcert.pem -infiles clientcert.csr
