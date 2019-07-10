..
      Copyright (c) 2019 AT&T Intellectual Property. All Rights Reserved.

      Licensed under the Apache License, Version 2.0 (the "License");
      you may not use this file except in compliance with the License.
      You may obtain a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

      Unless required by applicable law or agreed to in writing, software
      distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
      WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
      License for the specific language governing permissions and limitations
      under the License.

Instructions for installing REC using the Regional Controller and the REC Blueprint
===================================================================================

1. The Regional Controller should already be running somewhere (hopefully on a machine or
   VM dedicated for this purpose). See here_ for instructions on how to start the regional
   controller.

   .. _here: https://wiki.akraino.org/display/AK/Starting+the+Regional+Controller
   
2. Clone the *rec* repository using

   .. code-block:: bash

     git clone https://gerrit.akraino.org/r/rec.git

   We will use the following files from this repository:

  .. code-block:: bash

    ./REC_blueprint.yaml
    ./objects.yaml
    ./workflows/gencerts.sh
    ./workflows/REC_create.py

  You will need to provide a web server where some of these files may be fetched by the
  Regional Controller.
	
3. Edit the file *objects.yaml*.

   - Update the *nodes* stanza to define the nodes in your cluster, including the Out of
     Band IP address for each node, as well as the name of the hardware type.  Currently REC
     is defined to run on the three types of hardware listed in the *hardware* stanza.
   - If you want to give the edgesite a different name, update the 'edgesites' stanza.

4. Edit the file *REC_blueprint.yaml* to to update the URLs (the two lines that contain
   ``www.example.org``) for the create workflow script (*REC_create.py*), and the
   *gencerts.sh* script.  These URLs should point to the web server and path where you will
   store these files. The rest of the blueprint should be kept unchanged.

5. Create and edit a copy of *user_config.yaml*.  See these instructions_ on how to create
   this file.

   .. _instructions: https://wiki.akraino.org/display/AK/REC+Installation+Guide#RECInstallationGuide-Aboutuser_config.yaml

6. Copy the two workflows scripts and the *user_config.yaml* file to your web server.
   Note: the provided *gencerts.sh* just generates some self-signed certificates for use
   by the *remote-installer* Docker container, with some pre-defined defaults; if you want
   to provide your own certificates, you will need to modify or replace this script.
   Set and export the following variable:

   .. code-block:: bash

     export USER_CONFIG_URL=<URL of user_config.yaml>

7. Clone the *api-server* repository.  This provides the CLI tools used to interact with the
   Regional Controller.  Add the scripts from this repository to your PATH:

   .. code-block:: bash

     git clone https://gerrit.akraino.org/r/regional_controller/api-server
     export PATH=$PATH:$PWD/api-server/scripts

8. Define where the Regional Controller is located, as well as the login/password to use
   (the login/password shown here are the built-in values and do not need to be changed
   if you have not changed them on the Regional Controller):

   .. code-block:: bash

     export RC_HOST=<IP or DNS name of Regional Controller>
     export USER=admin
     export PW=admin123

9. Load the objects defined in *objects.yaml* into the Regional Controller using:

   .. code-block:: bash

     rc_loaddata -H $RC_HOST -u $USER -p $PW -A objects.yaml

10. Load the blueprint into the Regional Controller using:

   .. code-block:: bash

     rc_cli -H $RC_HOST -u $USER -p $PW blueprint create REC_blueprint.yaml

11. Get the UUIDs of the edgesite and the blueprint from the Regional Controller using:

    .. code-block:: bash

      rc_cli -H $RC_HOST -u $USER -p $PW blueprint list
      rc_cli -H $RC_HOST -u $USER -p $PW edgesite list

    These are needed to create the POD.  You will also see the UUID of the Blueprint displayed
    when you create the Blueprint in step 10 (it is at the tail end of the URL that is printed).
    Set and export them as the environment variables ESID and BPID.

    .. code-block:: bash

      export ESID=<UUID of edgesite in the RC>
      export BPID=<UUID of blueprint in the RC>

12. Figure out which REC ISO images you want to use to build your cluster.  These are
    located here:
    https://nexus.akraino.org/content/repositories/images-snapshots/TA/release-1/images/
    Figure out which build you want, and then set and export the following variables:

    .. code-block:: bash

	  export BUILD=<buildnumber>
	  export ISO_PRIMARY_URL=https://nexus.akraino.org/content/repositories/images-snapshots/TA/release-1/images/$BUILD/install.iso
	  export ISO_SECONDARY_URL=https://nexus.akraino.org/content/repositories/images-snapshots/TA/release-1/images/$BUILD/bootcd.iso

    Note: the Akraino Release 1 image is build #9.

13. Create the *POD.yaml* file as follows:

    .. code-block:: bash

	  cat > POD.yaml <<EOF
	  name: My_Radio_Edge_Cloud_POD
	  description: Put a description of the POD here.
	  blueprint: $BPID
	  edgesite: $ESID
	  yaml:
	    iso_primary: '$ISO_PRIMARY_URL'
	    iso_secondary: '$ISO_SECONDARY_URL'
	    input_yaml: '$USER_CONFIG_URL'
	    rc_host: $RC_HOST
	  EOF

14. Create the POD using:

    .. code-block:: bash

	  rc_cli -H $RC_HOST -u $USER -p $PW pod create POD.yaml

    This will cause the POD to be created, and the *REC_create.py* workflow script to be
    run on the Regional Controller's workflow engine. This in turn will pull in the ISO
    images, and install REC on your cluster.

15. If you want to monitor ongoing progess of the installation, you can issue periodic calls
    to monitor the POD with:

    .. code-block:: bash

  	  rc_cli -H $RC_HOST -u $USER -p $PW pod show $PODID

    where $PODID is the UUID of the POD. This will show all the messages logged by the
    workflow, as well as the current status of the workflow. The status will be WORKFLOW
    while the workflow is running, and wil change to ACTIVE if the workflow completes
    succesfully, or FAILED, if the workflow fails.
