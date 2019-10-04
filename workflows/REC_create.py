#!/usr/bin/python3
#
#       Copyright (c) 2019 AT&T Intellectual Property. All Rights Reserved.
#
#       Licensed under the Apache License, Version 2.0 (the "License");
#       you may not use this file except in compliance with the License.
#       You may obtain a copy of the License at
#
#           http://www.apache.org/licenses/LICENSE-2.0
#
#       Unless required by applicable law or agreed to in writing, software
#       distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#       WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#       License for the specific language governing permissions and limitations
#       under the License.
#

"""
REC_create.py - This workflow is used to create a REC POD by way of the remote-installer
container.   The remote-installer is started if it is not running.  Parameters passed to
this script (via the INPUT.yaml file) are:
  iso_primary - the main installer.iso file to use
  iso_secondary - the secondary bootcd.iso file
  input_yaml - the YAML file passed to remote_installer
  rc_host - the IP address or DNS name of the RC
"""

import datetime
import docker
import requests, urllib3
import os, sys, time, yaml
import POD

WORKDIR      = os.path.abspath(os.path.dirname(__file__))
RI_NAME      = 'remote-installer'
RI_IMAGE     = 'nexus3.akraino.org:10003/akraino/remote-installer:latest'
RI_DIR       = '/workflow/remote-installer'
CERT_DIR     = RI_DIR + '/certificates'
EXTERNALROOT = '/data'
NETWORK      = 'host'
WAIT_TIME    = 150
HTTPS_PORT   = 8443
API_PORT     = 15101
ADMIN_PASSWD = 'recAdm1n'
REMOVE_ISO   = False
HOST_IP      = '127.0.0.1'

def start(ds, **kwargs):
    # Read the user input from the POST
    global HOST_IP
    urllib3.disable_warnings()
    yaml = read_yaml(WORKDIR + '/INPUT.yaml')
    REC_ISO_IMAGE_NAME        = yaml['iso_primary']
    REC_PROVISIONING_ISO_NAME = yaml['iso_secondary']
    INPUT_YAML_URL            = yaml['input_yaml']
    HOST_IP                   = yaml['rc_host']
    CLOUDNAME                 = 'CL-'+POD.POD
    ISO                       = '%s/images/install-%s.iso' % (RI_DIR, POD.POD)
    BOOTISO                   = '%s/images/bootcd-%s.iso'  % (RI_DIR, POD.POD)
    USERCONF                  = '%s/user-configs/%s/user_config.yaml' % (RI_DIR, CLOUDNAME)

    print('-----------------------------------------------------------------------------------------------')
    print('                      POD is '+POD.POD)
    print('                CLOUDNAME is '+CLOUDNAME)
    print('                  WORKDIR is '+WORKDIR)
    print('                  HOST_IP is '+HOST_IP)
    print('             EXTERNALROOT is '+EXTERNALROOT)
    print('       REC_ISO_IMAGE_NAME is '+REC_ISO_IMAGE_NAME)
    print('REC_PROVISIONING_ISO_NAME is '+REC_PROVISIONING_ISO_NAME)
    print('           INPUT_YAML_URL is '+INPUT_YAML_URL)
    print('                      ISO is '+ISO)
    print('                  BOOTISO is '+BOOTISO)
    print('                 USERCONF is '+USERCONF)
    print('-----------------------------------------------------------------------------------------------')

    # Setup RI_DIR
    initialize_RI(CLOUDNAME)

    # Fetch the three files into WORKDIR
    fetchURL(REC_ISO_IMAGE_NAME,        WORKDIR + '/install.iso');
    fetchURL(REC_PROVISIONING_ISO_NAME, WORKDIR + '/bootcd.iso');
    fetchURL(INPUT_YAML_URL,            WORKDIR + '/user_config.yaml');

    # Link files to RI_DIR with unique names
    os.link(WORKDIR + '/install.iso', ISO)
    os.link(WORKDIR + '/bootcd.iso', BOOTISO)
    os.link(WORKDIR + '/user_config.yaml', USERCONF)
    PWFILE = '%s/user-configs/%s/admin_passwd' % (RI_DIR, CLOUDNAME)
    with open(PWFILE, "w") as f:
        f.write(ADMIN_PASSWD + '\n')

    # Start the remote_installer
    client = docker.from_env()
    namefilt = { 'name': RI_NAME }
    ri = client.containers.list(filters=namefilt)
    if len(ri) == 0:
        print(RI_NAME + ' is not running.')
        c = start_RI(client)

    else:
        print(RI_NAME + ' is running.')
        c = ri[0]

    # Send request to remote_installer
    id = send_request(HOST_IP, CLOUDNAME, ISO, BOOTISO)

    # Wait up to WAIT_TIME minutes for completion
    if wait_for_completion(HOST_IP, id, WAIT_TIME):
        print('Installation failed after %d minutes.' % (WAIT_TIME))
        sys.exit(1)

    # Remove the ISOs?
    if REMOVE_ISO:
        for iso in (WORKDIR + '/install.iso', ISO, WORKDIR + '/bootcd.iso', BOOTISO):
            os.unlink(iso)

    # Done!
    print('Installation complete!')
    # sys.exit(0)  Don't exit as this will cause the task to fail!
    return 'Complete.'

def read_yaml(input_file):
    print('Reading '+input_file+' ...')
    with open(input_file, 'r') as stream:
        try:
            return yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)
            sys.exit(1)

def send_request(ri_ip, CLOUDNAME, ISO, BOOTISO):
    URL     = 'https://%s:%d/v1/installations' % (ri_ip, API_PORT)
    print('Sending request to '+URL+' ...')
    headers = {'Content-type': 'application/json'}
    content = {
        'cloud-name': CLOUDNAME,
        'iso': os.path.basename(ISO),
        'provisioning-iso': os.path.basename(BOOTISO)
    }
    certs    = (CERT_DIR+'/clientcert.pem', CERT_DIR+'/clientkey.pem')
    response = requests.post(URL, json=content, headers=headers, cert=certs, verify=False)
    print(response)
    return response.json().get('uuid')

def create_podevent(msg='Default msg', level='INFO'):
    API_HOST = 'http://arc-api:8080'
    if os.environ.get('LOGGING_USER') and os.environ.get('LOGGING_PASSWORD'):
        payload  = {'name': os.environ['LOGGING_USER'], 'password': os.environ['LOGGING_PASSWORD']}
        response = requests.post(API_HOST+'/api/v1/login', json=payload)
        token    = response.headers['X-ARC-Token']
        headers  = {'X-ARC-Token': token}
        payload  = {'uuid': POD.POD, 'level': level, 'message': msg}
        response = requests.post(API_HOST+'/api/v1/podevent', headers=headers, json=payload)

def wait_for_completion(ri_ip, id, ntimes):
    """
    Wait (up to ntimes minutes) for the remote_installer to finish.
    Any status other than 'completed' is considered a failure.
    """
    status = 'ongoing'
    URL    = 'https://%s:%d/v1/installations/%s/state' % (ri_ip, API_PORT, id)
    certs  = (CERT_DIR+'/clientcert.pem', CERT_DIR+'/clientkey.pem')
    lastevent = ''
    while status == 'ongoing' and ntimes > 0:
        time.sleep(60)
        response = requests.get(URL, cert=certs, verify=False)
        j = response.json()
        t = (
            str(j.get('status')),
            str(j.get('percentage')),
            str(j.get('description'))
        )
        event = 'Status is %s (%s) %s' % t
        print('%s: %s' % (datetime.datetime.now().strftime('%x %X'), event))
        if event != lastevent:
            create_podevent(event)
        lastevent = event
        status = j.get('status')
        ntimes = ntimes - 1
    return status != 'completed'

def fetchURL(url, dest):
    print('Fetching '+url+' ...')
    r = requests.get(url)
    with open(dest, 'wb') as f1:
        f1.write(r.content)

def initialize_RI(CLOUDNAME):
    """ Create the directory structure needed by the remote-installer """
    dirs = (
        RI_DIR,
        RI_DIR+'/certificates',
        RI_DIR+'/images',
        RI_DIR+'/installations',
        RI_DIR+'/user-configs',
        RI_DIR+'/user-configs/'+CLOUDNAME
    )
    for dir in dirs:
        if not os.path.isdir(dir):
            print('mkdir '+dir)
            os.mkdir(dir)

def start_RI(client):
    """
    Start the remote-installer container (assumed to already be built somewhere).
    Before starting, make sure the certificates directory is populated.  If not,
    generate some self-signed certificates.
    """
    # If needed, create certificates (11 files) in RI_DIR/certificates
    if not os.path.exists(CERT_DIR+'/clientcert.pem') or not os.path.exists(CERT_DIR+'/clientkey.pem'):
        print('Generating some self-signed certificates.')
        script = WORKDIR + '/gencerts.sh'
        cmd = 'bash %s %s' % (script, RI_DIR+'/certificates')
        print('os.system('+cmd+')')
        os.system(cmd)

    print('Starting %s.' % RI_NAME)
    env = {
        'API_PORT': API_PORT, 'HOST_ADDR': HOST_IP, 'HTTPS_PORT': HTTPS_PORT,
        'PW': ADMIN_PASSWD, 'SSH_PORT': 22222
    }
    vols = {
        EXTERNALROOT+RI_DIR: {'bind': '/opt/remoteinstaller', 'mode': 'rw'}
    }
    try:
        c = client.containers.run(
            image=RI_IMAGE,
            name=RI_NAME,
            network_mode=NETWORK,
            environment=env,
            volumes=vols,
            detach=True,
            remove=True,
            privileged=True
        )

        # Wait 5 minutes for it to be running
        n = 0
        while c.status != 'running' and n < 10:
            time.sleep(30)
            c.reload()
            n = n + 1
        if c.status != 'running' and n >= 10:
            print('Container took to long to start!')
            sys.exit(1)
        return c

    except docker.errors.ImageNotFound as ex:
        # If the specified image does not exist.
        print(ex)
        sys.exit(1)

    except docker.errors.APIError as ex:
        # If the server returns an error.
        print(ex)
        sys.exit(1)

    except:
        print('other error!')
        sys.exit(1)
