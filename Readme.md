# Configuring CI/CD on OpenShift with Bamboo, Bitbucket and JFrog Artifactory

### Introduction

DevOps encourages collaboration, cooperation, and communication between developers and operations teams to improve the speed and quality of software development. One of the key principles of DevOps is automation, which reduces human error, provides consistent results, and even mitigates risks. With the help of automation, you and your team can build, test, and deploy software quickly and efficiently. 

### Learning objectives

In this tutorial, you will:  

* Set up a Bamboo environment, a Bitbucket environment and a JFrog Artifactory environment
* Configure a Bamboo plan
* Build Docker images using Bamboo and Source-to-Image(S2I) 
* Push Docker images to an external JFrog Artifactory
* Deploy Docker images to an OpenShift environment
* Integrate Bitbucket and Bamboo

## Prerequisites

* An OpenShift cluster

> In this tutorial, OpenShift v4.2 will be used.

* Download an OpenShift [Command Line Interface (CLI)](https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.2)

> Download the OpenShift CLI to the machine which serves as Bamboo server.

* Download and configure a [Bamboo Server](https://www.atlassian.com/software/bamboo/download)

> Follow the [Bamboo Installation Guide](https://confluence.atlassian.com/bamboo/bamboo-installation-guide-289276785.html) to install and configure the Bamboo server on a preferred OS.

* Download and configure a [Bitbucket Server](https://www.atlassian.com/software/bitbucket/download)

> Follow the [Bitbucket Server Installation Guide](https://confluence.atlassian.com/bitbucketserver/bitbucket-server-installation-guide-867338382.html) to install and configure the Bitbucket server on a preferred OS.

* Download and configure a [JFrog Container Registry](https://jfrog.com/container-registry/)

> Follow the [JFrog Artifactory Installation Guide](https://www.jfrog.com/confluence/display/JFROG/Installing+Artifactory) to install and configure the JFrog Container Registry on a preferred OS.

> `Recommendation:` It is convenient to install all these environments on the same machine, but it is recommended to separate the machines for more robustness.

Make sure that you have access to those ports.

* **open/public** - required for external communication.
* **closed/private** - only required for internal communication

### Bamboo Server ports

Application or service|Default port|Access
:-------------:|:-------------:|:-----:
Crowd|8085|Open/public
ActiveMQ/JMS|54663|Open/public (required for remote agents)

### Bitbucket Server ports

Application or service|Default port|Access
:-------------:|:-------------:|:-----:
Bitbucket|7990|Open/public
Bitbucket SSH|7999|Open/public (only required if SSH is enabled)
Elasticsearch|7992,7993|Open/public
Remove Elasticseach server|9200|Open/public (only required for Data Center)
Hazelcast|5701|Closed/private (only required for inter-node communication in Data Center)

### JFrog Artifactory ports

Application or service|Default port|Access
:-------------:|:-------------:|:-----:
Artifactory|8081|Open/public
Router|8082|Open/public
Access|8040,8045|Closed/private
Replicator|8048,9092|Closed/private
Web|8070|Closed/private
Metadata|8086|Closed/private
Router|8046,8047,8049|Closed/private

## Steps

Follow these steps to setup and run this tutorial.

1. [Set up a Nginx Reverse Proxy to JFrog Artifactory](#1-set-up-a-nginx-reverse-proxy-to-jfrog-artifactory)
2. [Create a Local Docker Repository on JFrog Artifactory](#2-create-a-local-docker-repository-on-jfrog-artifactory)
3. [Push an Example Spring Boot Project to Bitbucket Server](#3-push-an-example-spring-boot-project-to-bitbucket-server)
4. [Create a Link Between Bamboo and Bitbucket](#4-create-a-link-between-bamboo-and-bitbucket)
5. [Create a SSH Key Pair to Enable Access to Bitbucket over SSH](#5-create-a-ssh-key-pair-to-enable-access-to-bitbucket-over-ssh)
6. [Create a Bamboo Build Plan](#6-create-a-bamboo-build-plan)
7. [Configure Build Plan Stages and Jobs](#7-configure-build-plan-stages-and-jobs)
8. [Create an OpenShift Project](#8-create-an-openshift-project)
9. [Test the First Build Plan](#9-test-the-first-build-plan)

### 1. Set up a Nginx Reverse Proxy to JFrog Artifactory

Login to the machine that serves as JFrog Container Registry.

```
$ ssh <USER>@<SERVER_IP>
```

#### Installing Prebuilt CentOS/RHEL Packages

* Install the EPEL repository

``` 
$ sudo yum install epel-release
```

* Update the repository

``` 
$ sudo yum update
```

* Install Nginx Open Source

``` 
$ sudo yum install nginx
```

* Verify the installation

``` 
$ sudo nginx -v
nginx version: nginx/1.16.1
```

#### Installing Prebuilt Ubuntu Packages

* Update the Ubuntu repository information

``` 
$ sudo apt-get update
```

* Install the package

``` 
$ sudo apt-get install nginx
```

* Verify the installation

``` 
$ sudo nginx -v
nginx version: nginx/1.16.1 (Ubuntu)
```

After successfully completing the installation process, the next step is creating a TLS certificate for Nginx.

> **Note:** In this step, we will create a self-signed certificate. For this reason, your browser and other applications will warn you. If you want to use an officially signed certificate, you need a FQDN and a valid certificate authority.

* Move into a proper directory to create certificate

```
$ mkdir /etc/nginx/cert
```

* Create certificate using OpenSSL

```
$ sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/cert/nginx.key -out /etc/nginx/cert/nginx.crt
```

* Self-signed certificate is ready to use
```
$ ls /etc/nginx/cert
```

Now it's time to configure Nginx by editing configuration file. By default, the configuration file is named `nginx.conf` and placed in the directory `/usr/local/nginx/conf`, `/etc/nginx`, or `/usr/local/etc/nginx`.

* Locate the Nginx configuration file and open it with the help of an editor.

```
$ vim /etc/nginx/nginx.conf
```

* Replace the existing configuration with the following one.
> **Note:** Don't forget to replace the `<SERVER_IP>` value with the IP address of your machine in the configuration file.

```
events {}
http {
## add ssl entries when https has been set in config
ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
ssl_certificate      /etc/nginx/cert/nginx.crt;
ssl_certificate_key  /etc/nginx/cert/nginx.key;
ssl_session_cache shared:SSL:1m;
ssl_prefer_server_ciphers   on;
## server configuration
server {
    listen 443 ssl;

    server_name <SERVER_IP>;

    if ($http_x_forwarded_proto = '') {
        set $http_x_forwarded_proto  $scheme;
    }
    ## Application specific logs
    ## access_log /var/log/nginx/yourdomain.com-access.log timing;
    ## error_log /var/log/nginx/yourdomain.com-error.log;
    rewrite ^/$ /ui/ redirect;
    rewrite ^/ui$ /ui/ redirect;
    chunked_transfer_encoding on;
    client_max_body_size 0;
    location / {
        proxy_read_timeout  2400s;
        proxy_pass_header   Server;
        proxy_cookie_path   ~*^/.* /;
        proxy_pass          http://localhost:8082;
        proxy_next_upstream error timeout non_idempotent;
        proxy_next_upstream_tries    1;
        proxy_set_header    X-JFrog-Override-Base-Url $http_x_forwarded_proto://$host:$server_port;
        proxy_set_header    X-Forwarded-Port  $server_port;
        proxy_set_header    X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header    Host              $http_host;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
    }
  }
}
```

* Restart Nginx with the new configuration.

```
$ sudo systemctl restart nginx
```

We configured Nginx with a self-signed TLS certificate to make JFrog Container Registry secure. Now, open your favourite browser and gain access to the JFrog Artifactory's dashboard.

> You can access the dashboard with the link `https://<SERVER_IP>`

We expect to see a warning message on the first login.

![warning-message](./images/warning-message.png "Warning Message")

Remember, this is a self-signed certificate and the browser is trying to alert us. To continue, you must click on the `Accept Risk and Continue` button.

![the-first-login-page](./images/the-first-login-page.png "The First Login Page")

Great! You’re now ready for the next step.

### 2. Create a Local Docker Repository on JFrog Artifactory

If you chose `Docker` package type in the quick setup while configuring JFrog Artifactory, it probably created a `Local` repository, two `Remote` repositories and a `Virtual` repository for you.  However, it is a good practice to create our own Local Docker Repository even if a local repository has been created for us.

* Click on the `Repositories` button on the left navigation menu under the `Administration` tab. It will direct you to the repository page. After that, click on the `New Local Repository` button under the `Local` tab.

![repository-page](./images/repository-page.png "Repository Page")

* Select the `Docker` package type.

![docker-package-type](./images/docker-package-type.png "Docker Package Type")

* Give an arbitrary `Repository Key` to your repository and click on the `Save & Finish` button.

> **Note:** Give `my-local-repository` name to go along with the tutorial.

![my-local-repository](./images/my-local-repository.png "My Local Repository")

Now, it's time to test our image repository.

> **Note:** You will need Docker installed on your local machine.

* Open a terminal and login to your registry via Docker.

```
docker login <SERVER_IP>:443
```

![docker-login-error](./images/docker-login-error.png "Docker Login Error")

You will get an error message from Docker. This is because Docker doesn't trust the certificate. Follow the [Docker's documentation](https://docs.docker.com/registry/insecure/#deploy-a-plain-http-registry) to solve this problem.

After solving the certificate problem with Docker, push an arbitrary image to the repository to test it.

* Tag an arbitrary image with your server ip and repository key.

```
docker tag <ARBITRARY_IMAGE> <SERVER_IP>:443/<REPOSITORY_KEY>/<IMAGE_NAME>:<TAG>
```

* Push the tagged image to the repository.

```
docker push <SERVER_IP>:443/<REPOSITORY_KEY>/<IMAGE_NAME>:<TAG>
```

![docker-push-image](./images/docker-push-image.png "Docker Push Image")

The image is successfully pushed. You can see the pushed image on the web console. Click on the `Application` tab, expand the `JFrog Container Registry` option and click on the `Packages` button.

![docker-image-web-console](./images/docker-image-web-console.png "Docker Image Web Console")

Congratulations, you have successfully pushed the image to the repository!

### 3. Push an Example Spring Boot Project to Bitbucket Server

In this step, we will push an example Spring Boot Project to Bitbucket.

* Login to Bitbucket Server via the link `<BITBUCKET_SERVER_IP>:7990` and click on the `Create project` button.

![create-project](./images/create-project.png "Create Project")

* Give an arbitrary `Project name`, `Project key` and `Description`. After that, click on the `Create project` button.

> **Note:** Give `Spring Boot Example` as Project name, `SBE` as Project key to go along with the tutorial.

![project-name](./images/project-name.png "Project Name")

Now, we created a general project for our future repositories. In the next step, we should create a repository under that project. 

* Click on the `Create repository` button under the `Spring Boot Example` project.

![create-repository](./images/create-repository.png "Create Repository")

* Give an arbitrary `Name` and click on the `Create repository` button.

> **Note:** Give `Spring Boot Example` as name to go along with the tutorial.

![repository-name](./images/repository-name.png "Repository Name")

Get the example Spring Boot project under the `Spring Boot Example` directory in GitHub and push it to Bitbucket Server. Follow the `My code is ready to be pushed` section.

![push-example-project](./images/push-example-project.png "Push Example Project")

After pushing the example project, you will see the project under the repository.

![bitbucket-repo](./images/bitbucket-repo.png "Bitbucket Repo")

### 4. Create a Link Between Bamboo and Bitbucket

In this step we will create a link between Bamboo and Bitbucket. With help of this link, Bamboo will easily fetch the code that is stored in Bitbucket.

* Go to the Bamboo dashboard and click on the `Gear` symbol shown in the upper right corner. After that, click on the `Overview` button.

![bamboo-overview](./images/bamboo-overview.png "Bamboo Overview")

* Locate the `Manage Apps` section in the left menu and click on the `Application links` button.

![application-link](./images/application-link.png "Application Link")

* Enter the URL of Bitbucket server and click on the `Create new link` button.

![enter-the-url](./images/enter-the-url.png "Enter the URL")

* Click on the `Continue` button and it will redirect you to Bitbucket with the same page. Again, click on the `Continue` button.

![bitbucket-link-application](./images/bitbucket-link-application.png "Bitbucket Link Application")

We have successfully created the link between Bamboo and Bitbucket.

![successfully-linked](./images/successfully-linked.png "Successfully Linked")

Now, we will create a link for repository using the previously created link between Bamboo and Bitbucket.

* Locate the `Build Resources` section in the left menu and click on the `Linked Repositories` button. After that, click on the `Add repository` button.

![add-repository](./images/add-repository.png "Add Repository")

* Select the `Bitbucket Server / Stash` option.

![bitbucket-server-stash](./images/bitbucket-server-stash.png "Bitbucket Server / Stash")

Before creating the link for the repository, you should give an approval for the link.

* Click on the `Login & approve` button.

![login-approve](./images/login-approve.png "Login & Approve")

It will redirect you to Bitbucket to grant access to Bamboo.

* Click on the `Allow` button.

![allow-bitbucket](./images/allow-bitbucket.png "Allow Bitbucket")

Bitbucket granted the read and write access to Bamboo to access it's repositories. Now, we can create the repository link.

* Give an arbitrary name, select the repository and branch you wish to use. After that, click on the `Save repository` button.

> **Note:** Give `Spring Boot Example` as name to go along with the tutorial.

![save-repository](./images/save-repository.png "Save Repository")

We have successfully created the repository link.

### 5. Create a SSH Key Pair to Enable Access to Bitbucket over SSH

In this step, we will create a SSH key pair to enable access to Bitbucket Server. SSH key will be used by OpenShift to fetch the code. Bamboo also uses SSH key to fetch the code but it created its own SSH key in the previous step to access Bitbucket. We will create this SSH key just for OpenShift.


* Create a SSH key

> **Note:** Leave the passphrase empty.

```
$ ssh-keygen
```

![ssh-keygen](./images/ssh-keygen.png "ssh-keygen")

Now, we will add the public key to the repository to gain access.

* Open the public key and copy its content.

> **Note:** Make sure that you are in the directory that contains the ssh key.

```
$ cat id_rsa.pub
```

Go to the Bitbucket repository to add the public key.

* Click on the `Gear` symbol in the left menu. After that, click on the `Access keys` button.

![access-key](./images/access-key.png "Access Key")

You will see that Bamboo added its own SSH key to repository to gain access.

* Click on the `Add key` button. It will redirect you to a page. Paste the public key and keep the options as default. After that, click on the `Add key` button to save the key.

![add-key](./images/add-key.png "Add Key")

SSH key is added successfully. You can test it by cloning repository using SSH option.

> **Note:** We added SSH key to just one repository. If you want to add SSH key to account to gain access over whole repositories, go to the `Manage Account` section.

### 6. Create a Bamboo Build Plan

Build plans hold all the instructions to build, test and assemble your software. Whenever you make a change to your code, Bamboo triggers your build plan and notifies you of the result.

* Go to the Bamboo dashboard and click on the `Create` button on top of the page. After that, click on the `Create plan` button.

![create-build-plan](./images/create-build-plan.png "Create Build Plan")

* Give an arbitrary `Project name`, `Project key`, `Plan name` and `Plan key`. Select the `Repository host` as the previously linked repository. After that, click on the `Configure plan` button.

![configure-plan](./images/configure-plan.png "Configure Plan")

* Keep the settings as default and click on the `Save and continue` button.

> **Note:** Builds are normally run in the agent's native operating system. If you want to run your build in an isolated and controlled environment, you can do it with Docker.

![create-plan](./images/create-plan.png "Create Plan")

Congratulations! You have successfully created the build plan.

### 7. Configure Build Plan Stages and Jobs

Each stage within a plan represents a step within your build process. A stage may contain one or more jobs which Bamboo can execute in parallel. For example, you might have a stage for compilation jobs, followed by one or more stages for various testing jobs, followed by a stage for deployment jobs. 

* Click on the `Default Job` under the `Default Stage`.

![default-job](./images/default-job.png "Default Job")

* Click on the `Add task` button and choose `Script` as the task type.

![script-type](./images/script-type.png "Script Type")

We will create two scripts. One script is for build task, the other script is for deployment task. Firstly, we will start with build script.

* Give an arbitrary `Task description` and paste the script below into the `Script body` field. After that, click on the `Save` button.

```
# Login to the OpenShift cluster
oc login ${bamboo.OC_MASTER_API} -u ${bamboo.OC_USERNAME} -p ${bamboo.OC_PASSWORD} --insecure-skip-tls-verify
# Change the project
oc project spring-boot-example

# Check if the BuildConfig exists
if oc get bc spring-boot-example; then
# If yes, start a new build
oc start-build spring-boot-example
# If no, do the tasks respectively
else
# Create a secret that holds private key for fetching code from Bitbucket server
oc create secret generic bitbucket --from-literal=ssh-privatekey="$(echo ${bamboo.SSHKEY_PRIVATE} | base64 --decode)"
# Link the secret that is created in the previous step to the 'builder' service account
oc secrets link builder bitbucket
# Create a secret that holds login credentials of JFrog Artifactory
oc create secret docker-registry private-registry --docker-server=${bamboo.DOCKER_SERVER} --docker-username=${bamboo.DOCKER_USERNAME} --docker-password=${bamboo.DOCKER_PASSWORD}
# Link the secret that is created in the previous step to 'default' service account
oc secrets link default private-registry --for=pull
# Link the secret that is created in the previous step to the 'builder' service account
oc secrets link builder private-registry
# Create a BuildConfig that builds the source code using S2I(Source-to-Image) and pushes it to JFrog Artifactory
# If you gave different name to the Bitbucket repository or Docker local repository, don't forget to change them.
oc new-build redhat-openjdk18-openshift:1.5~ssh://git@${bamboo.BITBUCKET_SERVER}/sbe/spring-boot-example.git --name=spring-boot-example --source-secret=bitbucket --to-docker --to=${bamboo.DOCKER_SERVER}/my-local-repository/spring-boot-example:latest --push-secret=private-registry
fi

sleep 10
# Follow the build logs
oc logs bc/spring-boot-example -f
# Import the pushed image to the OpenShift cluster as ImageStream
oc import-image spring-boot-example:latest --confirm --from=${bamboo.DOCKER_SERVER}/my-local-repository/spring-boot-example:latest
```

![build-script](./images/build-script.png "Build Script")

* Again, click on the `Add task` button and choose `Script` as the task type. Give an arbitrary `Task description` and paste the script below into the `Script body` field. After that, click on the `Save` button.


```
# Check if DeploymentConfig exists
if ! oc get dc spring-boot-example; then
# If no, create a new deployment using created ImageStream
oc new-app spring-boot-example:latest --name=spring-boot-example
sleep 10
# Follow the deployment logs
oc logs dc/spring-boot-example -f
# Create a route for public access
oc expose svc spring-boot-example
fi
```

![deployment-script](./images/deployment-script.png "Deployment Script")

We configured the job for build and deployment tasks. Now, we need to define some environment variables for the scripts.

* Go back to the plan's configuration page and click on the `Variables` button.

![variables](./images/variables.png "Variables")

* Investigate the scripts and define corresponding environment variables respectively.

> **Note:** The access port to Bitbucket via SSH is `7999`.

> **Note:** The `SSHKEY_PRIVATE` environment variable is the base64 encoded value of the private key that is created in the previous step. Run the following command to get encoded value of the private key.

```
$ base64 id_rsa -w 0
```

![define-variables](./images/define-variables.png "Define Variables")

The plan is in the disabled mode. We need to enable it to use it.

* Click on the `Actions` button and select the `Enable plan` option to activate the plan.

![enable-plan](./images/enable-plan.png "Enable Plan")

Congratulations! Build plan is ready to use. But, before running the plan, we should create an openshift project.

### 8. Create an OpenShift Project

Bamboo will build and deploy an application under the `spring-boot-example` project. So, we need to create that project before starting the build process.

* Login to your OpenShift cluster and click on the `Projects` button under the `Home` pane. After that, click on the `Create Project` button and give the `spring-boot-example` value as the name.

![create-oc-project](./images/create-oc-project.png "Create OC Project")

* Click on the `Pods` button under the `Workloads` pane to see the pods that will be created by Bamboo.

![pods](./images/pods.png "Pods")

We are ready to make a test! 

### 9. Test the First Build Plan

Bamboo is finally ready to test. Let's run our first build plan.

* Go back to the build plan's dashboard and click on the `Run` button. After that, click on the `Run plan` button.

> **Note:** You can also commit a change to the Bitbucket repository. It also triggers the Bamboo plan. Remember, we have linked Bamboo and Bitbucket.

![run-plan](./images/run-plan.png "Run Plan")

After a few minutes, the build process ends with a success message.

![success-message](./images/success-message.png "Success Message")

The application is successfully deployed to the OpenShift cluster.

![openshift-success](./images/openshift-success.png "Openshift Success")

Let's check if image is pushed successfully.

* Click on the `Packages` button under the `JFrog Container Registry` pane.

![jfrog-artifactory](./images/jfrog-artifactory.png "JFrog Artifactory")

Let's check if application is running properly.

* Click on the `Routes` button under the `Networking` pane.

![route](./images/route.png "Route")

* Click on the link and append the `/users` path to the link.

![users](./images/users.png "Users")

Congratulations! You have successfully deployed the application and its services.