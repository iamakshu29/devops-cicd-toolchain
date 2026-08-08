# Taking reference from 

## 1. Terraform Code in cd 00_Setup/Infra/terraform/
- Give complete output in CLI end-to-end
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/00_Setup/Infra/terraform/ \
--framework terraform \
--soft-fail \
--output cli
```

- Give compacted output
- Which include the Checks name, resource-name, file-path and line
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/00_Setup/Infra/terraform/ \
--framework terraform \
--compact \
--soft-fail \
--output cli
```

- Give compacted output only for failed checks by skipping the mentioned checks.
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/00_Setup/Infra/terraform/ \
--framework terraform \
--skip-check CKV_AWS_126,CKV2_AWS_34 \
--compact \
--quiet \
--soft-fail \
--output cli
```

- Give compacted output for failed checks by skipping the mentioned checks in a file.
- reports/results_cli.txt
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/00_Setup/Infra/terraform/ \
--framework terraform \
--skip-check CKV_AWS_126,CKV2_AWS_34 \
--compact \
--quiet \
--soft-fail \
--output cli \
--output-file-path ./terraform_reports/
```


## 2. Dockerfile Code in cd Reference_Project/spring-petclinic/

- Get only the failed check
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/Reference_Project/spring-petclinic/ \
--framework dockerfile \
--soft-fail \
--quiet
```

- Get the failed check in compacted form
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/Reference_Project/spring-petclinic/ \
--framework dockerfile \
--soft-fail \
--quiet \
--compact
```

- Skipping the only Failed Check
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/Reference_Project/spring-petclinic/ \
--framework dockerfile \
--soft-fail \
--quiet \
--skip-check CKV_DOCKER_2
```

- Get the output in report for failed checks only
```bash
checkov -d /c/Users/Lenovo/Desktop/Pipeline/devops-cicd-toolchain/Reference_Project/spring-petclinic/ \
--framework dockerfile \
--soft-fail \
--quiet \
--output-file-path ./docker_reports/
```