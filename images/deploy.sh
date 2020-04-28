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
