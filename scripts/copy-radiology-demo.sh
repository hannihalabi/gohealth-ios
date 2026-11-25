#!/bin/sh
set -eu

# Test images never enter an ordinary Release/App Store archive.
if [ "${CONFIGURATION}" != "Debug" ]; then
    exit 0
fi

source_path="${SRCROOT}/GoHealth/RadiologyDemo"
destination_path="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/RadiologyDemo"
test -f "${source_path}/manifest.json"

# Write only declared output files. ditto can create undeclared .BC staging
# files when replacing existing resources, which Xcode correctly rejects.
/bin/mkdir -p "${destination_path}/images"
for name in manifest.json LAS-MIG.txt; do
    /bin/cat "${source_path}/${name}" > "${destination_path}/${name}"
done
for image in "${source_path}"/images/[0-9][0-9][0-9][0-9].jpg; do
    name="${image##*/}"
    /bin/cat "${image}" > "${destination_path}/images/${name}"
done
