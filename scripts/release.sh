#!/bin/bash

PROJECT_NAME="config-manager"

. .env

if [ "${GITLAB_TOKEN}" == "" ]; then
    echo "required variable \$GITLAB_TOKEN not set"
    exit 1
fi

TMPDIR=$(mktemp -d)

SHORT_REF=$(git rev-parse --short HEAD)
LONG_REF=$(git rev-parse HEAD)

FORK_ID=$(ht GET https://gitlab.cee.redhat.com/api/v4/projects/13582/forks?owned=true "PRIVATE-TOKEN:${GITLAB_TOKEN}" | jq '.[0].id')

if [ "${FORK_ID}" == "null" ]; then
    FORK_ID=$(ht POST https://gitlab.cee.redhat.com/api/v4/projects/13582/fork "PRIVATE-TOKEN:${GITLAB_TOKEN}" | jq '.id')
    
    while [ "$(ht GET https://gitlab.cee.redhat.com/api/v4/projects/${FORK_ID} "PRIVATE-TOKEN:${GITLAB_TOKEN}" | jq -r '.import_status')" != "finished" ]; do
        sleep 2
    done
fi

SSH_URL_TO_REPO=$(ht GET https://gitlab.cee.redhat.com/api/v4/projects/${FORK_ID} "PRIVATE-TOKEN:${GITLAB_TOKEN}" | jq -r '.ssh_url_to_repo')
FORKED_SSH_URL_TO_REPO=$(ht GET https://gitlab.cee.redhat.com/api/v4/projects/${FORK_ID} "PRIVATE-TOKEN:${GITLAB_TOKEN}" | jq -r '.forked_from_project.ssh_url_to_repo')

git clone --depth=1 "${SSH_URL_TO_REPO}" "${TMPDIR}/app-interface"

git -C "${TMPDIR}/app-interface" remote add upstream "${FORKED_SSH_URL_TO_REPO}"
git -C "${TMPDIR}/app-interface" pull upstream master
git -C "${TMPDIR}/app-interface" push origin master
git -C "${TMPDIR}/app-interface" checkout -b "${PROJECT_NAME}/prod-release-${SHORT_REF}"
OLD_REF=$(yq -r '.resourceTemplates[0].targets[] | select(.namespace."$ref" == "/services/insights/${PROJECT_NAME}/namespaces/${PROJECT_NAME}-prod.yml") | .ref' < "${TMPDIR}"/app-interface/data/services/insights/${PROJECT_NAME}/deploy.yml)
sed -i -e "s/${OLD_REF}/${LONG_REF}/" "${TMPDIR}"/app-interface/data/services/insights/${PROJECT_NAME}/deploy.yml
git -C "${TMPDIR}/app-interface" add data/services/insights/${PROJECT_NAME}/deploy.yml
git -C "${TMPDIR}/app-interface" commit -m "deploy(${PROJECT_NAME}): release ${SHORT_REF} to production"
git -C "${TMPDIR}/app-interface" show -1
git -C "${TMPDIR}/app-interface" push -u origin "${PROJECT_NAME}/prod-release-${SHORT_REF}"
ht POST https://gitlab.cee.redhat.com/api/v4/projects/"${FORK_ID}"/merge_requests "PRIVATE-TOKEN:${GITLAB_TOKEN}" id="${FORK_ID}" source_branch="${PROJECT_NAME}/prod-release-${SHORT_REF}" target_branch=master target_project_id=13582 title="deploy(${PROJECT_NAME}): release ${SHORT_REF} to production" | jq -r .web_url
rm -rf "${TMPDIR}"