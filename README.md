# Pouta Spark Course example

*Work in progress* 

# Overview

This repository is an example of how to setup a temporary course environment with 
Apache Spark and Jupyter notebooks in CSC's cPouta environment.

The procedure will use: 
* Ansible for setting up and configuring a basic cluster with one master and multiple slaves.
* Apache Ambari to set up Hortonworks Data Platform 
* Docker and tmpnb to serve Jupyter notebooks for the students

To use CSC cPouta cloud environment you will need

* credentials for Pouta
* basic knowledge of Pouta and OpenStack

See https://research.csc.fi/pouta-user-guide for details

# Step 0: Set up a bastion host

**NOTE: This whole step (Step 0) has to be done only once!**

http://en.wikipedia.org/wiki/Bastion_host

In case you don't have a readily available host for running OpenStack command line tools and Ansible, 
you can set one up in your cPouta project through https://pouta.csc.fi

Log into https://pouta.csc.fi

If you are member of multiple projects, select the desired one from the drop down list on top left

Create a new security group called, for example, 'bastion'

  - go to *Access and Security -> Security groups -> Create Security Group*
  - add rules to allow ssh for yourself and other admins
  - normal users do not need to access this hosts
  - keep the access list as small as possible to minimize exposure

Create an access key if you don't already have one

  - go to *Access and Security -> Keypairs -> Create/Import Keypair*

Boot a new VM from the latest CentOS 7 image that is provided by CSC

  - go to *Instances -> Launch Instance*
  - pick a name for the VM, for example 'bastion'
  - Flavor: mini
  - Instance boot source: Image
  - Image Name: Latest public Centos image (CentOS-7.0 at the time of writing)
  - Keypair: select your key
  - Security Groups: select *default* and *bastion*
  - Network: select the desired network (you probably only have one, which is the default)
  - Launch

Associate a floating IP (allocate one for the project if you don't already have a spare)

Log in to the bastion host with ssh as *cloud-user*

    ssh cloud-user@86.50.1XX.XXX:

Install dependencies and otherwise useful packages

    sudo yum install -y \
        dstat lsof bash-completion time tmux git xauth \
        screen nano vim bind-utils nmap-ncat git\
        centos-release-openstack python-novaclient \
        python-devel python-setuptools python-virtualenvwrapper
    
    sudo yum groupinstall -y "Development Tools"

update the system and reboot to bring the host up to date. Bonus: virtualenvwrapper gets activated 

    sudo yum update -y && sudo reboot

* import your OpenStack command line access configuration


  - see https://research.csc.fi/pouta-credentials how to export the openrc
  - use scp to copy the file to bastion from your workstation::

    [me@workstation ~]$ scp openrc.sh cloud-user@86.50.1XX.XXX:

# Step 1: Set up the virtual cluster

In this step we launch VMs in our cPouta project and configure them to act as a basis
for a simple cluster. You can run this on your management host, be it the bastion or your
laptop.

Enable / Check if you already have a virtuanenv by `workon ansible`. If yes, then skip this section.

Make a python virtualenv called 'ansible2' and populate it

    mkvirtualenv ansible2
    pip install "ansible>=2.0.1" shade dnspython funcsigs functools32

Source your OpenStack cPouta access credentials (actual filename will vary)::

    source ~/openrc.sh
    nova image-list
    
Create a new key for the cluster (adapt the name) and upload it to OpenStack (**NOTE: Only to be done if doing it for the first time!**)

    ssh-keygen -f ~/.ssh/id_rsa_mycluster
    nova keypair-add --pub-key ~/.ssh/id_rsa_mycluster my_key

Clone this example repo

    git clone https://github.com/tourunen/pouta-spark-course.git

Disable ssh host key checking (http://docs.ansible.com/ansible/intro_getting_started.html#host-key-checking).
Add an entry for all the hosts in your cPouta subnet. Use *ip* command to figure out your network address range.
    
    ip a
    
    vi ~/.ssh/config
    
    Host 192.168.1.*

        StrictHostKeyChecking no
        
Change the permissions on the config file

    chmod 600 ~/.ssh/config

Now there are 2 ways of modifying the configurations and then setting up the cluster:

  a. Examine *pouta-spark-course/playbooks/cluster.yml*, and edit to taste. And run:

    ansible-playbook -v pouta-spark-course/playbooks/cluster.yml

  **OR**

  b. Or override the variables in the command line, like in the example below and run: 
    
    ansible-playbook -v \
        -e cluster_name=my-hdp -e ssh_key=my_key -e bastion_secgroup=bastion \
        -e num_nodes=3 -e master_flavor=small -e node_flavor=small \
        pouta-spark-course/playbooks/cluster.yml


# Step 2: Install HDP with Ambari

**Proxying Solution Here (Instance Security Groups)**

Setup https for ambari server. First stop ambari-server
 
    sudo systemctl stop ambari-server
    
Then configure https 

    sudo ambari-server setup-security

    Security setup options...
    ===========================================================================
    Choose one of the following options: 
      [1] Enable HTTPS for Ambari server.
      [2] Encrypt passwords stored in ambari.properties file.
      [3] Setup Ambari kerberos JAAS configuration.
      [4] Setup truststore.
      [5] Import certificate to truststore.
    ===========================================================================
    Enter choice, (1-5): 1
    Do you want to configure HTTPS [y/n] (y)? 
    SSL port [8443] ? 
    Enter path to Certificate: /etc/ambari-server/ssl/server.crt
    Enter path to Private Key: /etc/ambari-server/ssl/server.key
    Please enter password for Private Key: 

Start the server once again

    sudo systemctl start ambari-server

Check the public ip of your cluster master (Openstack UI)
Open a browser and navigate to https://\<public-ip-of-the-cluster-master\>:8443

Login to the Ambari dashboard using default credentials

    username: admin
    password: admin

Login to your cluster master by using the internal IP of cluster master (Check Openstack UI).
Copy the auto-generated SSH Private Key, which we will use in the following section.

    cat ~/.ssh/id_rsa

On the Ambari dashboard click 'Launch Install Wizard'

1. **Getting Started** : Name your cluster (**We won't use this name in the following instructions. We will use the name defined earlier when ran cluster setup from bastion host**)
2. **Select Stack** : Choose the latest HDP version (i.e. 2.3)
3. **Install Options** : 
  - *Target Hosts* : Write down the following configuration
  ```
  <your-cluster-name>-master.novalocal
  <your-cluster-name>-node-[1-<num_nodes-defined-by-you>].novalocal
  ```
  - *Host Registration Information* : Paste the SSH Private Key from the cluster (Discussed earlier), including BEGIN and END lines.
  - *SSH User Account*: cloud-user
4. **Choose Services** : Just select HDFS, Yarn + MapReduce2, Zookeeper, Ambari Metrics and Spark. Uncheck every other option.
5. **Assign Masters**: Move every component to cluster master and keep only zookeepers in the other nodes
5. **Assign Slaves and Clients** : Check Client only for master. Check DataNode and NodeManager for all the nodes except master.
6. **Customize Services** : Click Next and then Click Proceed anyway on any pop-up dialog warning.
7. **Review** : Check the configurations and then press Deploy
8. **Install, Start and Test** : Wait for the installations to finish. If done, press Next
9. **Summary** : Press Complete

Now you have the Spark Cluster running and you can proceed with the next step.

# Step 3: Run notebooks with custom tmpnb

Add a directory to HDFS for the notebook user

    sudo -u hdfs hadoop fs -mkdir /user/jovyan
    sudo -u hdfs hadoop fs -chown -R jovyan /user/jovyan

*NOTE: If it says user exists, then skip*

Pull the jupyter/pyspark-notebook image to use with tmpnb

    sudo docker pull jupyter/pyspark-notebook

Build the docker image for a patched version of tmpnb

    sudo docker build -t csc/tmpnb https://github.com/apurva3000/tmpnb.git

Setup the proxy first to run tmpnb

    export TOKEN=$( head -c 30 /dev/urandom | xxd -p )
    
    sudo docker run --net=host -d -e CONFIGPROXY_AUTH_TOKEN=$TOKEN --name=proxy jupyter/configurable-http-proxy --default-target http://127.0.0.1:9999

Generate a password hash for the notebooks

    sudo docker run jupyter/pyspark-notebook python3 -c "from IPython.lib import passwd; print(passwd('dont_use_this'))"
    
Now run the image which we just built and tagged. This runs 2 notebook containers, keeping tmpnb in the foreground - 
good for debugging

    sudo docker run -it \
        --net=host \
        -e CONFIGPROXY_AUTH_TOKEN=$TOKEN \
        -v /var/run/docker.sock:/docker.sock \
        csc/tmpnb \
        python orchestrate.py \
            --pool_size=2 \
            --host_directories=/usr/hdp/:/usr/hdp/:ro,/etc/hadoop/:/etc/hadoop/:ro \
            --host_network=True \
            --image='jupyter/pyspark-notebook' \
            --command='start-notebook.sh \
                "--NotebookApp.base_url={base_path} \
                --ip=0.0.0.0 \
                --port={port} \
                --NotebookApp.password=THE_HASH_FROM_ABOVE \
                --NotebookApp.trust_xheaders=True"'

After the containers start running (Can be checked by `sudo docker ps -a`), open the browser and point to http://\<public-ip>:8000

Now open a Jupyter Python3 notebook and write the following code.

    import os
    os.environ["PYSPARK_PYTHON"]="/opt/conda/bin/python3"
    os.environ["YARN_CONF_DIR"]="/etc/hadoop/conf/"
    os.environ["SPARK_HOME"]="/usr/hdp/current/spark-client"
    os.environ["HDP_VERSION"]="current"
    
    import pyspark
    conf = pyspark.SparkConf()
    conf.set("spark.master", "yarn-client")
    conf.setAppName("Yarn Jupyter")
    sc = pyspark.SparkContext(conf=conf) 
    
    sc.version

Dont't forget to stop the SparkContext when done with `sc.stop()`

# Step 4: Clean up

To clean up the resources after the course is done, or to have a clean slate for another deployment, there is 
a playbook called *cluster_destroy.yml*. By default it does not do anything, all the actions have to be enabled
from the command line, just to be on a safe side.

Run these on your management/bastion host.
 
To remove the nodes and the master, but leave the HDFS data volumes and security groups:

    ansible-playbook -v \
        -e cluster_name=my-hdp -e num_nodes=4 \ 
        -e remove_master=1 \
        -e remove_nodes=1 \
        pouta-spark-course/playbooks/cluster_destroy.yml

To remove the nodes, master, all volumes and security groups:

    ansible-playbook -v \
        -e cluster_name=my-hdp -e num_nodes=4 \
        -e remove_master=1 -e remove_master_volumes=1 \
        -e remove_nodes=1 -e remove_node_volumes=1 \
        -e remove_security_groups=1 \
        pouta-spark-course/playbooks/cluster_destroy.yml
