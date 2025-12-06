# Preparation
Install the CLI. [Instructions is here](https://support.workbench.verily.com/docs/guides/cli/cli_install_and_run/)

- Authenticate with your Google account
- Create a workspace
- Add Data from Catalog (On Web UI)

# Nextflow setup
[Read this page](https://support.workbench.verily.com/docs/guides/workflows/nextflow/)

### Connect with your workspace
`wb workspace set –id=<workspace-id>`

### Create storage for Nextflow run logs and output
```
wb resource create gcs-bucket --id=nf_files \
--description="Bucket for Nextflow run logs and output."
```
### Add the longgwas repository
```
wb resource add-ref git-repo \
--id=longgwas \
--repo-url=https://github.com/hirotaka-i/long-gwas-pipeline.git
```
You can check the repository list by `wb resource list`

### Create an app instance to run Nextflow
```
wb app create gcp --app-config=jupyter-lab \
  --id=nextflow-jupyterlab \
  --description="JupyterLab notebook for running Nextflow"
```

This workspace has the following environment variables set in advance:
- GOOGLE_CLOUD_PROJECT
- GOOGLE_PROJECT
- GOOGLE_SERVICE_ACCOUNT_EMAIL
- WORKBENCH_USER_EMAIL

### Run
VM on the workspace doesn't have docker installed in the default. So standard profile or local profile do not work. You have to run the pipeline with gcp profile which uses google batch service.


```bash
# Specify variables to be used in nextflow.config
export STORE_ROOT='gs://<your-bucket-name>'
export PROJECT_NAME='testrun'

# Run the pipeline
wb nextflow -log z_$(date +%Y%m%d_%H%M%S).log run main.nf -profile gcb -params-file params.yml -resume
```

**Note:** The `STORE_ROOT` environment variable should point to your GCS bucket when using the `gcb` profile. Do not set it when running other pipelines locally, or specify a local work directory with `-w /tmp/work`.

Job list can be checked by
```bash
wb gcloud batch jobs list
```

## Using Seqera Platform (Recommended)

Using Nextflow Tower (Seqera Platform) is recommended to monitor runs and debug issues. To enable Tower monitoring:

1. Get your Tower access token from https://cloud.seqera.io/tokens
2. Set the token as an environment variable:

```bash
export TOWER_ACCESS_TOKEN='<your-tower-access-token>'
wb nextflow -log z_$(date +%Y%m%d_%H%M%S).log run main.nf -profile gcb -params-file params.yml -with-tower -resume
```

Tower provides:
- Real-time pipeline monitoring with web UI
- Detailed task logs and error messages (solves Cloud Logging permission issues)
- Resource usage metrics to optimize CPU/memory allocation
- Run history and comparison