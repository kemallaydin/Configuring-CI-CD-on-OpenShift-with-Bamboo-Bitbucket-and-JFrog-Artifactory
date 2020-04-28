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
