00_Setup -> Infra ->
Execute - sh jenkins_nodes_setup.sh apply

After The Infra got Created

Create the Cosing Key with Password - `cosign generate-key-pair`

Add the Env Variables in env_setup.sh for Jenkins Configuration.
- base64 encoded cosign.key, jenkins new public_IP 

Copy that Script scp -i "jenkins_master" -r ../jenkins/env_setup/ ubuntu@44.208.21.101:/tmp/

Execute - sh env_setup.sh in EC2 Jenkins_Master

Regarding Jenkins

1. Add OWASP related thing manually, they are not present in Jenkins CasC.
2. Copy the Cosign.key to local and upload as secret file in credentials in Jenkins. (As I stored the key and using the same key everytime, no need to do every time)
3. Copy the Pipeline and run it.
