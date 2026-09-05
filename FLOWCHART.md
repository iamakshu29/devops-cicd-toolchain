00_Setup -> Infra ->
Execute - sh jenkins_nodes_setup.sh apply

After The Infra got Created

Create the Cosing Key with Password

Add the Env Variables in env_setup.sh for Jenkins Configuration.

Copy that Script scp -i "jenkins_master" env_setup.sh ubuntu@<public_ip>:/tmp/

Execute - sh env_setup.sh in EC2 Jenkins_Master

Regarding Jenkins

1. Add OWASP related thing manually, they are not present in Jenkins CasC.
2. Copy the Pipeline and run it.
